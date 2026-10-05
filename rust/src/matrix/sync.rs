use std::{
    future::Future,
    sync::{Arc, Mutex, PoisonError},
};

use futures_util::{pin_mut, Stream, StreamExt};
use matrix_sdk::{Client, SessionChange};
use matrix_sdk_ui::{
    room_list_service::State as RoomListState,
    sync_service::{State as SyncServiceState, SyncService},
    RoomListService,
};
use tokio::{
    sync::{broadcast::error::RecvError, watch},
    task::AbortHandle,
};
use tracing::{debug, info, warn};

use crate::api::{error::MatrixError, room::SyncStateDto};

pub(crate) struct SyncSession {
    service: Arc<SyncService>,
    session_expired: watch::Sender<bool>,
    tasks: Mutex<Vec<AbortHandle>>,
}

impl SyncSession {
    pub(crate) async fn start(client: &Client) -> Result<Self, MatrixError> {
        // Offline mode turns network failures into a recoverable `Offline` state
        // instead of stopping the sync for good.
        let service = SyncService::builder(client.clone())
            .with_offline_mode()
            .build()
            .await
            .map_err(|error| {
                warn!(%error, "Could not build the sync service");
                MatrixError::Unknown
            })?;

        let session = Self {
            service: Arc::new(service),
            session_expired: watch::channel(false).0,
            tasks: Mutex::default(),
        };
        session.spawn(watch_session(
            client.clone(),
            session.service.clone(),
            session.session_expired.clone(),
        ));
        session.spawn(log_state_changes(session.service.clone()));
        session.spawn(resume_send_queue(client.clone(), session.service.clone()));
        session.service.start().await;
        info!("Sync started");
        Ok(session)
    }

    pub(crate) fn room_list_service(&self) -> Arc<RoomListService> {
        self.service.room_list_service()
    }

    pub(crate) fn state_updates(
        &self,
        emit: impl FnMut(SyncStateDto) -> bool + Send + 'static,
    ) -> impl Future<Output = ()> + Send + 'static {
        let service = self.service.clone();
        let session_expired = self.session_expired.subscribe();
        async move {
            let sync_states = service.state();
            let room_list_states = service.room_list_service().state();
            combine_states(
                sync_states.get(),
                sync_states,
                room_list_states.get(),
                room_list_states,
                session_expired,
                emit,
            )
            .await;
        }
    }

    pub(crate) fn spawn(&self, task: impl Future<Output = ()> + Send + 'static) {
        let handle = tokio::spawn(task).abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }

    // Aborting the forwarding tasks drops their sinks, which closes the Dart streams.
    pub(crate) async fn stop(&self) {
        self.service.stop().await;
        let tasks = std::mem::take(&mut *self.tasks.lock().unwrap_or_else(PoisonError::into_inner));
        for task in tasks {
            task.abort();
        }
        info!("Sync stopped");
    }
}

impl Drop for SyncSession {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
    }
}

// In offline mode the sync service keeps retrying even when the token was revoked,
// so a rejected token is detected here and the sync is stopped.
async fn watch_session(
    client: Client,
    service: Arc<SyncService>,
    session_expired: watch::Sender<bool>,
) {
    let mut changes = client.subscribe_to_session_changes();
    loop {
        match changes.recv().await {
            Ok(SessionChange::UnknownToken(_)) => {
                info!("Access token rejected by the homeserver, stopping the sync");
                session_expired.send_replace(true);
                service.stop().await;
                return;
            }
            Ok(SessionChange::TokensRefreshed) | Err(RecvError::Lagged(_)) => {}
            Err(RecvError::Closed) => return,
        }
    }
}

// Runs for the whole session, independently of anyone listening from Dart, so the
// log shows every transition of the services behind the connection indicator.
async fn log_state_changes(service: Arc<SyncService>) {
    let mut sync_states = service.state();
    let mut room_list_states = service.room_list_service().state();
    debug!(state = ?sync_states.get(), "Sync service state");
    debug!(state = ?room_list_states.get(), "Room list state");

    loop {
        tokio::select! {
            Some(state) = sync_states.next() => debug!(?state, "Sync service state changed"),
            Some(state) = room_list_states.next() => debug!(?state, "Room list state changed"),
            else => return,
        }
    }
}

// A network failure disables the send queue of the room, keeping the message queued.
// Re-enabling it when the sync runs again sends those messages without user action.
async fn resume_send_queue(client: Client, service: Arc<SyncService>) {
    let mut sync_states = service.state();
    while let Some(state) = sync_states.next().await {
        if matches!(state, SyncServiceState::Running) && !client.send_queue().is_enabled() {
            info!("Connection is back, resuming the send queue");
            client.send_queue().set_enabled(true).await;
        }
    }
}

pub(crate) async fn combine_states(
    mut sync: SyncServiceState,
    sync_updates: impl Stream<Item = SyncServiceState>,
    mut room_list: RoomListState,
    room_list_updates: impl Stream<Item = RoomListState>,
    mut session_expired: watch::Receiver<bool>,
    mut emit: impl FnMut(SyncStateDto) -> bool,
) {
    pin_mut!(sync_updates, room_list_updates);
    let mut last = None;

    loop {
        let state = sync_state(&sync, &room_list, *session_expired.borrow());
        if last != Some(state) {
            debug!(?state, ?sync, ?room_list, "Sync status emitted");
            if !emit(state) {
                return;
            }
            last = Some(state);
        }

        tokio::select! {
            next = sync_updates.next() => match next {
                Some(next) => sync = next,
                None => return,
            },
            next = room_list_updates.next() => match next {
                Some(next) => room_list = next,
                None => return,
            },
            changed = session_expired.changed() => if changed.is_err() { return },
        }
    }
}

pub(crate) fn sync_state(
    sync: &SyncServiceState,
    room_list: &RoomListState,
    session_expired: bool,
) -> SyncStateDto {
    if session_expired {
        return SyncStateDto::SessionExpired;
    }
    match sync {
        SyncServiceState::Running => match room_list {
            RoomListState::Running => SyncStateDto::Connected,
            RoomListState::Init | RoomListState::SettingUp | RoomListState::Recovering => {
                SyncStateDto::Syncing
            }
            RoomListState::Error { .. } | RoomListState::Terminated { .. } => SyncStateDto::Offline,
        },
        SyncServiceState::Idle => SyncStateDto::Syncing,
        SyncServiceState::Offline | SyncServiceState::Error(_) | SyncServiceState::Terminated => {
            SyncStateDto::Offline
        }
    }
}

#[cfg(test)]
mod tests {
    use tokio::{
        sync::mpsc::{self, UnboundedReceiver, UnboundedSender},
        task::JoinHandle,
    };

    use super::*;

    fn stopped(from: RoomListState) -> Box<RoomListState> {
        Box::new(from)
    }

    #[test]
    fn running_room_list_means_connected() {
        assert_eq!(
            sync_state(&SyncServiceState::Running, &RoomListState::Running, false),
            SyncStateDto::Connected
        );
    }

    #[test]
    fn room_list_still_loading_means_syncing() {
        for room_list in [
            RoomListState::Init,
            RoomListState::SettingUp,
            RoomListState::Recovering,
        ] {
            assert_eq!(
                sync_state(&SyncServiceState::Running, &room_list, false),
                SyncStateDto::Syncing
            );
        }
    }

    #[test]
    fn sync_not_started_yet_means_syncing() {
        assert_eq!(
            sync_state(&SyncServiceState::Idle, &RoomListState::Init, false),
            SyncStateDto::Syncing
        );
    }

    #[test]
    fn offline_or_stopped_sync_means_offline() {
        for sync in [SyncServiceState::Offline, SyncServiceState::Terminated] {
            assert_eq!(
                sync_state(&sync, &RoomListState::Running, false),
                SyncStateDto::Offline
            );
        }
    }

    #[test]
    fn failed_room_list_means_offline() {
        let room_list = RoomListState::Error {
            from: stopped(RoomListState::Running),
        };

        assert_eq!(
            sync_state(&SyncServiceState::Running, &room_list, false),
            SyncStateDto::Offline
        );
    }

    #[test]
    fn rejected_token_wins_over_any_other_state() {
        assert_eq!(
            sync_state(&SyncServiceState::Running, &RoomListState::Running, true),
            SyncStateDto::SessionExpired
        );
        assert_eq!(
            sync_state(&SyncServiceState::Idle, &RoomListState::Init, true),
            SyncStateDto::SessionExpired
        );
    }

    fn updates<T: Send + 'static>() -> (UnboundedSender<T>, impl Stream<Item = T>) {
        let (sender, receiver) = mpsc::unbounded_channel();
        let stream = futures_util::stream::unfold(receiver, |mut receiver| async move {
            receiver.recv().await.map(|value| (value, receiver))
        });
        (sender, stream)
    }

    struct Combiner {
        sync: UnboundedSender<SyncServiceState>,
        room_list: UnboundedSender<RoomListState>,
        session_expired: watch::Sender<bool>,
        emitted: UnboundedReceiver<SyncStateDto>,
        task: JoinHandle<()>,
    }

    fn combiner(sync: SyncServiceState, room_list: RoomListState) -> Combiner {
        let (sync_sender, sync_updates) = updates();
        let (room_list_sender, room_list_updates) = updates();
        let (session_expired, session_expired_receiver) = watch::channel(false);
        let (emit_sender, emitted) = mpsc::unbounded_channel();
        let task = tokio::spawn(combine_states(
            sync,
            sync_updates,
            room_list,
            room_list_updates,
            session_expired_receiver,
            move |state| emit_sender.send(state).is_ok(),
        ));
        Combiner {
            sync: sync_sender,
            room_list: room_list_sender,
            session_expired,
            emitted,
            task,
        }
    }

    #[tokio::test]
    async fn emits_the_initial_status() {
        let mut combiner = combiner(SyncServiceState::Idle, RoomListState::Init);

        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Syncing));
    }

    #[tokio::test]
    async fn emits_offline_when_only_the_sync_service_changes() {
        let mut combiner = combiner(SyncServiceState::Running, RoomListState::Running);
        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Connected));

        combiner
            .sync
            .send(SyncServiceState::Offline)
            .expect("send sync state");

        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Offline));
    }

    #[tokio::test]
    async fn follows_the_room_list_while_the_sync_service_runs() {
        let mut combiner = combiner(SyncServiceState::Running, RoomListState::SettingUp);
        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Syncing));

        combiner
            .room_list
            .send(RoomListState::Running)
            .expect("send room list state");

        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Connected));
    }

    #[tokio::test]
    async fn skips_updates_that_do_not_change_the_status() {
        let mut combiner = combiner(SyncServiceState::Running, RoomListState::Running);
        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Connected));

        combiner
            .room_list
            .send(RoomListState::Running)
            .expect("send room list state");
        combiner
            .sync
            .send(SyncServiceState::Running)
            .expect("send sync state");
        combiner
            .sync
            .send(SyncServiceState::Offline)
            .expect("send sync state");

        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Offline));
    }

    #[tokio::test]
    async fn emits_session_expired() {
        let mut combiner = combiner(SyncServiceState::Running, RoomListState::Running);
        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Connected));

        combiner.session_expired.send_replace(true);

        assert_eq!(
            combiner.emitted.recv().await,
            Some(SyncStateDto::SessionExpired)
        );
    }

    #[tokio::test]
    async fn stops_when_nobody_listens_anymore() {
        let mut combiner = combiner(SyncServiceState::Running, RoomListState::Running);
        assert_eq!(combiner.emitted.recv().await, Some(SyncStateDto::Connected));

        drop(combiner.emitted);
        combiner
            .sync
            .send(SyncServiceState::Offline)
            .expect("send sync state");

        combiner.task.await.expect("combiner finished");
    }
}
