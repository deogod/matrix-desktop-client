use std::{
    io,
    path::{Path, PathBuf},
};

use flutter_rust_bridge::frb;
use matrix_sdk::Client;
use tokio::sync::Mutex;
use tracing::warn;

use crate::{
    api::{
        error::MatrixError,
        session::{LogoutOutcomeDto, SessionDto},
    },
    matrix::{auth, homeserver::parse_homeserver_input, store},
};

#[frb(opaque)]
pub struct MatrixClientHandle {
    allow_insecure_localhost: bool,
    active: Mutex<Option<ActiveSession>>,
}

struct ActiveSession {
    client: Client,
    data_dir: PathBuf,
}

impl MatrixClientHandle {
    #[frb(sync)]
    pub fn new(allow_insecure_localhost: bool) -> Self {
        Self {
            allow_insecure_localhost,
            active: Mutex::new(None),
        }
    }

    pub async fn login(
        &self,
        homeserver: String,
        username: String,
        password: String,
        data_dir: String,
        passphrase: String,
    ) -> Result<SessionDto, MatrixError> {
        let homeserver = parse_homeserver_input(&homeserver, self.allow_insecure_localhost)?;
        let data_dir = PathBuf::from(data_dir);
        let mut active = self.active.lock().await;

        // Every login gets a new empty store. Previous stores are only removed after the
        // login succeeds, so a failed attempt keeps a saved session restorable.
        let new_store = store::create_store(&data_dir).map_err(storage_error)?;
        let result = auth::login(
            homeserver,
            &username,
            &password,
            &new_store,
            &passphrase,
            self.allow_insecure_localhost,
        )
        .await;

        match result {
            Ok((client, session)) => {
                *active = Some(ActiveSession {
                    client,
                    data_dir: data_dir.clone(),
                });
                remove_other_stores(&data_dir, &new_store.id);
                Ok(session)
            }
            Err(error) => {
                remove_store(&data_dir, &new_store.id);
                Err(error)
            }
        }
    }

    pub async fn restore_session(
        &self,
        session: SessionDto,
        data_dir: String,
        passphrase: String,
    ) -> Result<(), MatrixError> {
        let data_dir = PathBuf::from(data_dir);
        let mut active = self.active.lock().await;
        *active = None;

        // An empty crypto store would get new keys for a device the server already knows.
        let Some(store_path) = store::existing_store(&data_dir, &session.store_id) else {
            warn!("No local store to restore the session from");
            return Err(MatrixError::Storage);
        };

        let store_id = session.store_id.clone();
        let client = auth::restore(
            session,
            &store_path,
            &passphrase,
            self.allow_insecure_localhost,
        )
        .await?;

        if let Err(error) = auth::check_session(&client).await {
            drop(client);
            remove_store(&data_dir, &store_id);
            return Err(error);
        }

        *active = Some(ActiveSession {
            client,
            data_dir: data_dir.clone(),
        });
        // Leftovers from a login that was interrupted before finishing.
        remove_other_stores(&data_dir, &store_id);
        Ok(())
    }

    pub async fn logout(&self) -> Result<LogoutOutcomeDto, MatrixError> {
        let mut active = self.active.lock().await;
        let Some(ActiveSession { client, data_dir }) = active.take() else {
            return Ok(LogoutOutcomeDto::Complete);
        };

        let outcome = auth::logout(&client).await;
        drop(client);
        store::remove_all_stores(&data_dir).map_err(storage_error)?;
        Ok(outcome)
    }
}

fn storage_error(error: io::Error) -> MatrixError {
    warn!(%error, "Store operation failed");
    MatrixError::Storage
}

fn remove_store(data_dir: &Path, id: &str) {
    if let Err(error) = store::remove_store(data_dir, id) {
        warn!(%error, "Could not remove the store");
    }
}

fn remove_other_stores(data_dir: &Path, keep_id: &str) {
    if let Err(error) = store::remove_other_stores(data_dir, keep_id) {
        warn!(%error, "Could not remove previous stores");
    }
}
