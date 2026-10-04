use std::{
    io,
    path::{Path, PathBuf},
};

use flutter_rust_bridge::frb;
use matrix_sdk::Client;
use tokio::sync::Mutex;
use tracing::warn;

use crate::{
    api::{error::MatrixError, session::SessionDto},
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
        *active = None;

        // A new passphrase cannot open a previous store, so every login starts from scratch.
        let store_path = store::reset_store(&data_dir).map_err(storage_error)?;
        let result = auth::login(
            homeserver,
            &username,
            &password,
            &store_path,
            &passphrase,
            self.allow_insecure_localhost,
        )
        .await;

        match result {
            Ok((client, session)) => {
                *active = Some(ActiveSession { client, data_dir });
                Ok(session)
            }
            Err(error) => {
                clear_store(&data_dir);
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
        if !store::store_exists(&data_dir) {
            warn!("No local store to restore the session from");
            return Err(MatrixError::Storage);
        }

        let client = auth::restore(
            session,
            &store::store_path(&data_dir),
            &passphrase,
            self.allow_insecure_localhost,
        )
        .await?;

        if let Err(error) = auth::check_session(&client).await {
            drop(client);
            clear_store(&data_dir);
            return Err(error);
        }

        *active = Some(ActiveSession { client, data_dir });
        Ok(())
    }

    pub async fn logout(&self) -> Result<(), MatrixError> {
        let mut active = self.active.lock().await;
        let Some(ActiveSession { client, data_dir }) = active.take() else {
            return Ok(());
        };

        auth::logout(&client).await;
        drop(client);
        store::remove_store(&data_dir).map_err(storage_error)
    }
}

fn storage_error(error: io::Error) -> MatrixError {
    warn!(%error, "Store operation failed");
    MatrixError::Storage
}

fn clear_store(data_dir: &Path) {
    if let Err(error) = store::remove_store(data_dir) {
        warn!(%error, "Could not remove the store");
    }
}
