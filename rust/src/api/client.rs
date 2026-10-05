use std::{
    io,
    path::{Path, PathBuf},
};

use anyhow::anyhow;
use flutter_rust_bridge::frb;
use matrix_sdk::Client;
use tokio::sync::Mutex;
use tracing::warn;

use crate::{
    api::{
        error::MatrixError,
        room::{RoomDto, SyncStateDto},
        session::{LogoutOutcomeDto, SessionDto},
        timeline::TimelineHandle,
    },
    frb_generated::StreamSink,
    matrix::{auth, homeserver::parse_homeserver_input, rooms, store, sync::SyncSession, timeline},
};

#[frb(opaque)]
pub struct MatrixClientHandle {
    allow_insecure_localhost: bool,
    active: Mutex<Option<ActiveSession>>,
}

struct ActiveSession {
    client: Client,
    data_dir: PathBuf,
    sync: SyncSession,
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
        let (client, session) = match result {
            Ok(logged_in) => logged_in,
            Err(error) => {
                remove_store(&data_dir, &new_store.id);
                return Err(error);
            }
        };

        let sync = match SyncSession::start(&client).await {
            Ok(sync) => sync,
            Err(error) => {
                // A session that cannot sync is useless, so it is closed on the server too.
                auth::logout(&client).await;
                drop(client);
                remove_store(&data_dir, &new_store.id);
                return Err(error);
            }
        };

        if let Some(previous) = active.take() {
            previous.sync.stop().await;
        }
        *active = Some(ActiveSession {
            client,
            data_dir: data_dir.clone(),
            sync,
        });
        remove_other_stores(&data_dir, &new_store.id);
        Ok(session)
    }

    pub async fn restore_session(
        &self,
        session: SessionDto,
        data_dir: String,
        passphrase: String,
    ) -> Result<(), MatrixError> {
        let data_dir = PathBuf::from(data_dir);
        let mut active = self.active.lock().await;
        if let Some(previous) = active.take() {
            previous.sync.stop().await;
        }

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

        let sync = SyncSession::start(&client).await?;
        *active = Some(ActiveSession {
            client,
            data_dir: data_dir.clone(),
            sync,
        });
        // Leftovers from a login that was interrupted before finishing.
        remove_other_stores(&data_dir, &store_id);
        Ok(())
    }

    pub async fn logout(&self) -> Result<LogoutOutcomeDto, MatrixError> {
        let mut active = self.active.lock().await;
        let Some(ActiveSession {
            client,
            data_dir,
            sync,
        }) = active.take()
        else {
            return Ok(LogoutOutcomeDto::Complete);
        };

        sync.stop().await;
        let outcome = auth::logout(&client).await;
        drop(sync);
        drop(client);
        store::remove_all_stores(&data_dir).map_err(storage_error)?;
        Ok(outcome)
    }

    pub async fn stop_sync(&self) {
        if let Some(session) = self.active.lock().await.as_ref() {
            session.sync.stop().await;
        }
    }

    // Stream functions report problems through the sink: an `Err` returned here would
    // not reach the Dart stream.
    pub async fn sync_state(&self, sink: StreamSink<SyncStateDto>) {
        let active = self.active.lock().await;
        let Some(session) = active.as_ref() else {
            let _ = sink.add(SyncStateDto::SessionExpired);
            return;
        };

        let updates = session
            .sync
            .state_updates(move |state| sink.add(state).is_ok());
        session.sync.spawn(updates);
    }

    pub async fn rooms(&self, sink: StreamSink<Vec<RoomDto>>) {
        let active = self.active.lock().await;
        let Some(session) = active.as_ref() else {
            let _ = sink.add_error(anyhow!("No active session"));
            return;
        };
        let Ok(room_list) = rooms::all_rooms(&session.sync.room_list_service()).await else {
            let _ = sink.add_error(anyhow!("Could not open the room list"));
            return;
        };

        let client = session.client.clone();
        session
            .sync
            .spawn(rooms::forward_rooms(room_list, client, move |rooms| {
                sink.add(rooms).is_ok()
            }));
    }

    pub async fn open_timeline(&self, room_id: String) -> Result<TimelineHandle, MatrixError> {
        let active = self.active.lock().await;
        let session = active.as_ref().ok_or(MatrixError::SessionExpired)?;
        let timeline =
            timeline::open(&session.client, &session.sync.room_list_service(), &room_id).await?;
        Ok(TimelineHandle::new(timeline))
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
