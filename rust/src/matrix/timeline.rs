use std::sync::Arc;

use futures_util::{pin_mut, StreamExt};
use matrix_sdk::{
    ruma::{events::room::message::RoomMessageEventContent, RoomId, UserId},
    Client,
};
use matrix_sdk_base::crypto::types::events::UtdCause;
use matrix_sdk_ui::{
    eyeball_im::Vector,
    timeline::{
        EncryptedMessage, EventSendState, MsgLikeKind, Profile, RoomExt, Timeline, TimelineDetails,
        TimelineItem, TimelineItemContent,
    },
    RoomListService,
};
use tracing::warn;

use crate::{
    api::{
        error::MatrixError,
        room::MessageKindDto,
        timeline::{SendStateDto, TimelineItemDto, UndecryptableReasonDto},
    },
    matrix::message::message_summary,
};

const PAGE_SIZE: u16 = 20;

pub(crate) async fn open(
    client: &Client,
    room_list_service: &RoomListService,
    room_id: &str,
) -> Result<Arc<Timeline>, MatrixError> {
    let room_id = RoomId::parse(room_id).map_err(|error| {
        warn!(%error, "Invalid room id");
        MatrixError::Unknown
    })?;
    let Some(room) = client.get_room(&room_id) else {
        warn!(%room_id, "Room not found");
        return Err(MatrixError::Unknown);
    };

    // The room list sync only brings the latest event of each room per response; the
    // subscription makes the open room receive every new event.
    room_list_service
        .reset_and_add_room_subscriptions(&[&room_id])
        .await;

    let timeline = room.timeline().await.map_err(|error| {
        warn!(%error, "Could not open the timeline");
        MatrixError::Unknown
    })?;
    Ok(Arc::new(timeline))
}

// Same approach as the room list: the diffs are applied on the Rust side and the whole
// list of messages is sent on every change. Items that are not messages (date
// dividers, read markers, state events) are kept as `None` so indexes still match.
pub(crate) async fn forward_items(
    timeline: Arc<Timeline>,
    mut emit: impl FnMut(Vec<TimelineItemDto>) -> bool,
) {
    let (initial, updates) = timeline.subscribe().await;
    pin_mut!(updates);

    let mut items: Vector<Option<TimelineItemDto>> =
        initial.iter().map(|item| item_dto(item)).collect();
    if !emit(messages(&items)) {
        return;
    }
    while let Some(diffs) = updates.next().await {
        for diff in diffs {
            diff.map(|item| item_dto(&item)).apply(&mut items);
        }
        if !emit(messages(&items)) {
            return;
        }
    }
}

fn messages(items: &Vector<Option<TimelineItemDto>>) -> Vec<TimelineItemDto> {
    items.iter().flatten().cloned().collect()
}

pub(crate) async fn send_text(timeline: &Timeline, body: &str) -> Result<(), MatrixError> {
    let body = body.trim();
    if body.is_empty() {
        return Ok(());
    }
    // Only queues the message: the timeline shows it right away as a local echo and
    // its send state tells whether it reached the server.
    timeline
        .send(RoomMessageEventContent::text_plain(body).into())
        .await
        .map(|_| ())
        .map_err(|error| {
            warn!(%error, "Could not queue the message");
            MatrixError::Unknown
        })
}

pub(crate) async fn paginate_backwards(timeline: &Timeline) -> Result<bool, MatrixError> {
    // Loading history only fails in practice when the server cannot be reached.
    timeline
        .paginate_backwards(PAGE_SIZE)
        .await
        .map_err(|error| {
            warn!(%error, "Could not load older messages");
            MatrixError::Network
        })
}

fn item_dto(item: &TimelineItem) -> Option<TimelineItemDto> {
    let event = item.as_event()?;
    let TimelineItemContent::MsgLike(content) = event.content() else {
        return None;
    };
    let (kind, body, undecryptable_reason) = msg_like_parts(&content.kind);

    Some(TimelineItemDto {
        id: item.unique_id().0.clone(),
        sender_id: event.sender().to_string(),
        sender_name: sender_name(event.sender_profile(), event.sender()),
        kind,
        body,
        undecryptable_reason,
        timestamp_ms: i64::try_from(u64::from(event.timestamp().0)).unwrap_or(i64::MAX),
        is_own: event.is_own(),
        send_state: send_state(event.send_state()),
    })
}

pub(crate) fn msg_like_parts(
    kind: &MsgLikeKind,
) -> (
    MessageKindDto,
    Option<String>,
    Option<UndecryptableReasonDto>,
) {
    match kind {
        MsgLikeKind::Message(message) => {
            let (kind, body) = message_summary(message.msgtype());
            (kind, body.map(str::to_owned), None)
        }
        MsgLikeKind::Sticker(_) => (MessageKindDto::Sticker, None, None),
        MsgLikeKind::Redacted => (MessageKindDto::Redacted, None, None),
        MsgLikeKind::UnableToDecrypt(message) => (
            MessageKindDto::Encrypted,
            None,
            Some(undecryptable_reason(message)),
        ),
        _ => (MessageKindDto::Other, None, None),
    }
}

fn undecryptable_reason(message: &EncryptedMessage) -> UndecryptableReasonDto {
    match message {
        EncryptedMessage::MegolmV1AesSha2 { cause, .. } => reason_for(*cause),
        _ => UndecryptableReasonDto::Unknown,
    }
}

pub(crate) fn reason_for(cause: UtdCause) -> UndecryptableReasonDto {
    match cause {
        UtdCause::SentBeforeWeJoined => UndecryptableReasonDto::SentBeforeJoined,
        UtdCause::HistoricalMessageAndBackupIsDisabled
        | UtdCause::HistoricalMessageAndDeviceIsUnverified => {
            UndecryptableReasonDto::HistoryUnavailable
        }
        UtdCause::WithheldForUnverifiedOrInsecureDevice => UndecryptableReasonDto::UnverifiedDevice,
        UtdCause::WithheldBySender => UndecryptableReasonDto::WithheldBySender,
        UtdCause::VerificationViolation | UtdCause::UnsignedDevice | UtdCause::UnknownDevice => {
            UndecryptableReasonDto::UntrustedSender
        }
        UtdCause::Unknown => UndecryptableReasonDto::Unknown,
    }
}

pub(crate) fn send_state(state: Option<&EventSendState>) -> SendStateDto {
    match state {
        None | Some(EventSendState::Sent { .. }) => SendStateDto::Sent,
        Some(EventSendState::NotSentYet { .. }) => SendStateDto::Sending,
        Some(EventSendState::SendingFailed { .. }) => SendStateDto::Failed,
    }
}

pub(crate) fn sender_name(profile: &TimelineDetails<Profile>, sender: &UserId) -> String {
    match profile {
        TimelineDetails::Ready(Profile {
            display_name: Some(name),
            ..
        }) if !name.trim().is_empty() => name.clone(),
        _ => sender.localpart().to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::{owned_event_id, owned_user_id};

    use super::*;

    #[test]
    fn redacted_and_sticker_have_no_body() {
        assert_eq!(
            msg_like_parts(&MsgLikeKind::Redacted),
            (MessageKindDto::Redacted, None, None)
        );
    }

    #[test]
    fn undecryptable_message_carries_a_reason() {
        let message = MsgLikeKind::UnableToDecrypt(EncryptedMessage::Unknown);

        assert_eq!(
            msg_like_parts(&message),
            (
                MessageKindDto::Encrypted,
                None,
                Some(UndecryptableReasonDto::Unknown)
            )
        );
    }

    #[test]
    fn undecryptable_reasons_follow_the_sdk_cause() {
        let cases = [
            (UtdCause::Unknown, UndecryptableReasonDto::Unknown),
            (
                UtdCause::SentBeforeWeJoined,
                UndecryptableReasonDto::SentBeforeJoined,
            ),
            (
                UtdCause::HistoricalMessageAndBackupIsDisabled,
                UndecryptableReasonDto::HistoryUnavailable,
            ),
            (
                UtdCause::HistoricalMessageAndDeviceIsUnverified,
                UndecryptableReasonDto::HistoryUnavailable,
            ),
            (
                UtdCause::WithheldForUnverifiedOrInsecureDevice,
                UndecryptableReasonDto::UnverifiedDevice,
            ),
            (
                UtdCause::WithheldBySender,
                UndecryptableReasonDto::WithheldBySender,
            ),
            (
                UtdCause::VerificationViolation,
                UndecryptableReasonDto::UntrustedSender,
            ),
            (
                UtdCause::UnsignedDevice,
                UndecryptableReasonDto::UntrustedSender,
            ),
            (
                UtdCause::UnknownDevice,
                UndecryptableReasonDto::UntrustedSender,
            ),
        ];
        for (cause, reason) in cases {
            assert_eq!(reason_for(cause), reason, "{cause:?}");
        }
    }

    #[test]
    fn remote_and_confirmed_messages_are_sent() {
        let sent = EventSendState::Sent {
            event_id: owned_event_id!("$event:example.org"),
        };

        assert_eq!(send_state(None), SendStateDto::Sent);
        assert_eq!(send_state(Some(&sent)), SendStateDto::Sent);
    }

    #[test]
    fn local_echo_is_sending() {
        let sending = EventSendState::NotSentYet { progress: None };

        assert_eq!(send_state(Some(&sending)), SendStateDto::Sending);
    }

    #[test]
    fn failed_send_is_reported() {
        let failed = EventSendState::SendingFailed {
            error: Arc::new(matrix_sdk::Error::AuthenticationRequired),
            is_recoverable: true,
        };

        assert_eq!(send_state(Some(&failed)), SendStateDto::Failed);
    }

    #[test]
    fn sender_name_prefers_the_profile() {
        let sender = owned_user_id!("@alice:example.org");
        let profile = TimelineDetails::Ready(Profile {
            display_name: Some("Alice".to_owned()),
            display_name_ambiguous: false,
            avatar_url: None,
        });

        assert_eq!(sender_name(&profile, &sender), "Alice");
    }

    #[test]
    fn sender_name_falls_back_to_the_localpart() {
        let sender = owned_user_id!("@alice:example.org");
        let blank = TimelineDetails::Ready(Profile {
            display_name: Some("  ".to_owned()),
            display_name_ambiguous: false,
            avatar_url: None,
        });

        assert_eq!(sender_name(&TimelineDetails::Pending, &sender), "alice");
        assert_eq!(sender_name(&TimelineDetails::Unavailable, &sender), "alice");
        assert_eq!(sender_name(&blank, &sender), "alice");
    }
}
