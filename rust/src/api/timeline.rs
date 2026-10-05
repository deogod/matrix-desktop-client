use std::sync::Arc;

use flutter_rust_bridge::frb;
use matrix_sdk_ui::timeline::Timeline;

use crate::{
    api::{error::MatrixError, room::MessageKindDto},
    frb_generated::StreamSink,
    matrix::{task::OwnedTask, timeline},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineItemDto {
    pub id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub kind: MessageKindDto,
    pub body: Option<String>,
    pub undecryptable_reason: Option<UndecryptableReasonDto>,
    pub timestamp_ms: i64,
    pub is_own: bool,
    pub send_state: SendStateDto,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendStateDto {
    Sending,
    Sent,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UndecryptableReasonDto {
    Unknown,
    SentBeforeJoined,
    HistoryUnavailable,
    UnverifiedDevice,
    WithheldBySender,
    UntrustedSender,
}

// One per open timeline panel. Dropping it (Dart `dispose`) aborts the task that feeds
// the Dart stream right away, even if the room never changes again.
#[frb(opaque)]
pub struct TimelineHandle {
    timeline: Arc<Timeline>,
    task: OwnedTask,
}

impl TimelineHandle {
    pub(crate) fn new(timeline: Arc<Timeline>) -> Self {
        Self {
            timeline,
            task: OwnedTask::default(),
        }
    }

    pub async fn messages(&self, sink: StreamSink<Vec<TimelineItemDto>>) {
        let task = tokio::spawn(timeline::forward_items(
            self.timeline.clone(),
            move |items| sink.add(items).is_ok(),
        ));
        self.task.replace(task.abort_handle());
    }

    pub async fn send_message(&self, body: String) -> Result<(), MatrixError> {
        timeline::send_text(&self.timeline, &body).await
    }

    pub async fn paginate_backwards(&self) -> Result<bool, MatrixError> {
        timeline::paginate_backwards(&self.timeline).await
    }
}
