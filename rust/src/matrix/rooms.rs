use futures_util::{pin_mut, StreamExt};
use matrix_sdk::{
    latest_events::{LatestEventValue, LatestEvents},
    ruma::{
        events::{room::message::MessageType, AnyMessageLikeEventContent, AnySyncTimelineEvent},
        serde::Raw,
        OwnedUserId, UserId,
    },
    Client, Room, RoomDisplayName,
};
use matrix_sdk_ui::{
    eyeball_im::{Vector, VectorDiff},
    room_list_service::{
        filters::{
            new_filter_all, new_filter_deduplicate_versions, new_filter_joined, new_filter_not,
            new_filter_space,
        },
        RoomList, RoomListItem,
    },
    RoomListService,
};
use tracing::warn;
use unicode_segmentation::UnicodeSegmentation;

use crate::{
    api::{
        error::MatrixError,
        room::{LastMessageDto, MessageKindDto, RoomDto},
    },
    matrix::message::message_summary,
};

const PAGE_SIZE: usize = 200;
const PREVIEW_MAX_CHARS: usize = 200;

pub(crate) async fn all_rooms(service: &RoomListService) -> Result<RoomList, MatrixError> {
    service.all_rooms().await.map_err(|error| {
        warn!(%error, "Could not open the room list");
        MatrixError::Unknown
    })
}

// The list is kept on the Rust side and sent whole on every change: only the rooms
// touched by a diff are converted again, and Dart never has to replay diffs.
pub(crate) async fn forward_rooms(
    room_list: RoomList,
    client: Client,
    mut emit: impl FnMut(Vec<RoomDto>) -> bool,
) {
    let (entries, controller) = room_list.entries_with_dynamic_adapters(PAGE_SIZE);
    controller.set_filter(Box::new(new_filter_all(vec![
        Box::new(new_filter_joined()),
        Box::new(new_filter_not(Box::new(new_filter_space()))),
        Box::new(new_filter_deduplicate_versions()),
    ])));
    pin_mut!(entries);

    let latest_events = client.latest_events().await;
    let mut rooms = Vector::new();
    while let Some(diffs) = entries.next().await {
        for diff in diffs {
            convert_diff(diff, latest_events).await.apply(&mut rooms);
        }
        if !emit(rooms.iter().cloned().collect()) {
            return;
        }
    }
}

async fn convert_diff(
    diff: VectorDiff<RoomListItem>,
    latest_events: &LatestEvents,
) -> VectorDiff<RoomDto> {
    match diff {
        VectorDiff::Append { values } => VectorDiff::Append {
            values: convert_all(values, latest_events).await,
        },
        VectorDiff::Clear => VectorDiff::Clear,
        VectorDiff::PushFront { value } => VectorDiff::PushFront {
            value: room_dto(&value, latest_events).await,
        },
        VectorDiff::PushBack { value } => VectorDiff::PushBack {
            value: room_dto(&value, latest_events).await,
        },
        VectorDiff::PopFront => VectorDiff::PopFront,
        VectorDiff::PopBack => VectorDiff::PopBack,
        VectorDiff::Insert { index, value } => VectorDiff::Insert {
            index,
            value: room_dto(&value, latest_events).await,
        },
        VectorDiff::Set { index, value } => VectorDiff::Set {
            index,
            value: room_dto(&value, latest_events).await,
        },
        VectorDiff::Remove { index } => VectorDiff::Remove { index },
        VectorDiff::Truncate { length } => VectorDiff::Truncate { length },
        VectorDiff::Reset { values } => VectorDiff::Reset {
            values: convert_all(values, latest_events).await,
        },
    }
}

async fn convert_all(rooms: Vector<RoomListItem>, latest_events: &LatestEvents) -> Vector<RoomDto> {
    let mut converted = Vector::new();
    for room in rooms {
        converted.push_back(room_dto(&room, latest_events).await);
    }
    converted
}

async fn room_dto(room: &Room, latest_events: &LatestEvents) -> RoomDto {
    // Latest events are only computed for rooms someone listens to. Listening again
    // is a no-op, and a new value arrives later as an update of this room.
    if let Err(error) = latest_events.listen_to_room(room.room_id()).await {
        warn!(%error, "Could not listen to the latest event of a room");
    }

    let name = room.display_name().await.ok().and_then(room_name);
    let latest = latest_message(&room.latest_event(), room.own_user_id());
    let sender_name = match &latest {
        Some(LatestMessage {
            sender: Some(sender),
            is_own: false,
            ..
        }) => Some(member_name(room, sender).await),
        _ => None,
    };

    RoomDto {
        id: room.room_id().to_string(),
        initial: room_initial(name.as_deref()),
        name,
        last_message: latest.map(|message| message.into_dto(sender_name)),
        last_activity_ms: room
            .latest_event_timestamp()
            .and_then(|timestamp| i64::try_from(u64::from(timestamp.0)).ok()),
        unread_count: count(room.num_unread_messages()),
        unread_mentions: count(room.num_unread_mentions()),
        is_direct: room.is_direct().await.unwrap_or(false),
    }
}

async fn member_name(room: &Room, user_id: &UserId) -> String {
    let display_name = match room.get_member_no_sync(user_id).await {
        Ok(Some(member)) => member.display_name().map(str::to_owned),
        _ => None,
    };
    display_name.unwrap_or_else(|| user_id.localpart().to_owned())
}

fn count(value: u64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct LatestMessage {
    sender: Option<OwnedUserId>,
    is_own: bool,
    kind: MessageKindDto,
    body: Option<String>,
}

impl LatestMessage {
    fn into_dto(self, sender_name: Option<String>) -> LastMessageDto {
        LastMessageDto {
            sender_name,
            is_own: self.is_own,
            kind: self.kind,
            body: self.body,
        }
    }
}

pub(crate) fn latest_message(
    value: &LatestEventValue,
    own_user_id: &UserId,
) -> Option<LatestMessage> {
    match value {
        LatestEventValue::Remote(event) => {
            let sender = event.sender();
            let (kind, body) = if event.kind.is_utd() {
                (MessageKindDto::Encrypted, None)
            } else {
                remote_content(event.raw())
            };
            Some(LatestMessage {
                is_own: sender.as_deref() == Some(own_user_id),
                sender,
                kind,
                body,
            })
        }
        LatestEventValue::LocalIsSending(local)
        | LatestEventValue::LocalCannotBeSent(local)
        | LatestEventValue::LocalHasBeenSent { value: local, .. } => {
            let (kind, body) = match local.content.deserialize() {
                Ok(content) => message_content(&content),
                Err(_) => (MessageKindDto::Other, None),
            };
            Some(LatestMessage {
                sender: Some(own_user_id.to_owned()),
                is_own: true,
                kind,
                body,
            })
        }
        LatestEventValue::RemoteInvite { .. } | LatestEventValue::None => None,
    }
}

fn remote_content(raw: &Raw<AnySyncTimelineEvent>) -> (MessageKindDto, Option<String>) {
    match raw.deserialize() {
        Ok(AnySyncTimelineEvent::MessageLike(event)) => match event.original_content() {
            Some(content) => message_content(&content),
            None => (MessageKindDto::Redacted, None),
        },
        Ok(AnySyncTimelineEvent::State(_)) | Err(_) => (MessageKindDto::Other, None),
    }
}

fn message_content(content: &AnyMessageLikeEventContent) -> (MessageKindDto, Option<String>) {
    match content {
        AnyMessageLikeEventContent::RoomMessage(message) => message_type(&message.msgtype),
        AnyMessageLikeEventContent::Sticker(_) => (MessageKindDto::Sticker, None),
        AnyMessageLikeEventContent::RoomEncrypted(_) => (MessageKindDto::Encrypted, None),
        _ => (MessageKindDto::Other, None),
    }
}

fn message_type(message: &MessageType) -> (MessageKindDto, Option<String>) {
    let (kind, body) = message_summary(message);
    (kind, body.map(preview_text))
}

// One line is enough for a preview, and long messages should not cross the bridge
// on every room list update.
fn preview_text(body: &str) -> String {
    body.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(PREVIEW_MAX_CHARS)
        .collect()
}

pub(crate) fn room_name(name: RoomDisplayName) -> Option<String> {
    match name {
        RoomDisplayName::Named(name)
        | RoomDisplayName::Aliased(name)
        | RoomDisplayName::Calculated(name)
        | RoomDisplayName::EmptyWas(name) => Some(name),
        RoomDisplayName::Empty => None,
    }
}

pub(crate) fn room_initial(name: Option<&str>) -> String {
    name.map(|name| name.trim().trim_start_matches(['#', '@', '!']).trim_start())
        .and_then(|name| name.graphemes(true).next())
        .map(str::to_uppercase)
        .unwrap_or_else(|| "#".to_owned())
}

#[cfg(test)]
mod tests {
    use matrix_sdk::{
        deserialized_responses::{TimelineEvent, UnableToDecryptInfo, UnableToDecryptReason},
        latest_events::LocalLatestEventValue,
        ruma::{
            events::room::message::RoomMessageEventContent, owned_user_id,
            MilliSecondsSinceUnixEpoch,
        },
        store::SerializableEventContent,
    };
    use serde_json::{json, Value};

    use super::*;

    fn own_user() -> OwnedUserId {
        owned_user_id!("@me:example.org")
    }

    fn remote(event: Value) -> LatestEventValue {
        let raw = serde_json::from_value(event).expect("raw event");
        LatestEventValue::Remote(TimelineEvent::from_plaintext(raw))
    }

    fn message(sender: &str, content: Value) -> Value {
        json!({
            "type": "m.room.message",
            "event_id": "$event:example.org",
            "sender": sender,
            "origin_server_ts": 1_700_000_000_000_u64,
            "content": content,
        })
    }

    fn summary(value: &LatestEventValue) -> Option<(MessageKindDto, Option<String>, bool)> {
        latest_message(value, &own_user())
            .map(|message| (message.kind, message.body, message.is_own))
    }

    #[test]
    fn text_message_keeps_body_and_sender() {
        let value = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.text", "body": "oi" }),
        ));

        let latest = latest_message(&value, &own_user()).expect("latest message");

        assert_eq!(latest.kind, MessageKindDto::Text);
        assert_eq!(latest.body.as_deref(), Some("oi"));
        assert_eq!(latest.sender, Some(owned_user_id!("@alice:example.org")));
        assert!(!latest.is_own);
    }

    #[test]
    fn own_remote_message_is_marked_as_own() {
        let value = remote(message(
            "@me:example.org",
            json!({ "msgtype": "m.text", "body": "oi" }),
        ));

        assert_eq!(
            summary(&value),
            Some((MessageKindDto::Text, Some("oi".to_owned()), true))
        );
    }

    #[test]
    fn emote_and_notice_keep_their_body() {
        let emote = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.emote", "body": "acena" }),
        ));
        let notice = remote(message(
            "@bot:example.org",
            json!({ "msgtype": "m.notice", "body": "aviso" }),
        ));

        assert_eq!(
            summary(&emote),
            Some((MessageKindDto::Emote, Some("acena".to_owned()), false))
        );
        assert_eq!(
            summary(&notice),
            Some((MessageKindDto::Notice, Some("aviso".to_owned()), false))
        );
    }

    #[test]
    fn media_messages_only_report_their_kind() {
        let cases = [
            ("m.image", MessageKindDto::Image),
            ("m.video", MessageKindDto::Video),
            ("m.audio", MessageKindDto::Audio),
            ("m.file", MessageKindDto::File),
        ];
        for (msgtype, kind) in cases {
            let value = remote(message(
                "@alice:example.org",
                json!({ "msgtype": msgtype, "body": "nome.bin", "url": "mxc://example.org/abc" }),
            ));

            assert_eq!(summary(&value), Some((kind, None, false)), "{msgtype}");
        }
    }

    #[test]
    fn location_is_reported_as_location() {
        let value = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.location", "body": "Aqui", "geo_uri": "geo:51.5,-0.1" }),
        ));

        assert_eq!(
            summary(&value),
            Some((MessageKindDto::Location, None, false))
        );
    }

    #[test]
    fn redacted_message_is_reported_as_redacted() {
        let value = remote(json!({
            "type": "m.room.message",
            "event_id": "$event:example.org",
            "sender": "@alice:example.org",
            "origin_server_ts": 1_700_000_000_000_u64,
            "content": {},
            "unsigned": {
                "redacted_because": {
                    "type": "m.room.redaction",
                    "event_id": "$redaction:example.org",
                    "sender": "@alice:example.org",
                    "origin_server_ts": 1_700_000_000_001_u64,
                    "redacts": "$event:example.org",
                    "content": {},
                },
            },
        }));

        assert_eq!(
            summary(&value),
            Some((MessageKindDto::Redacted, None, false))
        );
    }

    #[test]
    fn undecryptable_message_is_reported_as_encrypted() {
        let raw = serde_json::from_value(json!({
            "type": "m.room.encrypted",
            "event_id": "$event:example.org",
            "sender": "@alice:example.org",
            "origin_server_ts": 1_700_000_000_000_u64,
            "content": {
                "algorithm": "m.megolm.v1.aes-sha2",
                "ciphertext": "AwgAEnAC",
                "device_id": "DEVICE",
                "sender_key": "key",
                "session_id": "session",
            },
        }))
        .expect("raw event");
        let info = UnableToDecryptInfo {
            session_id: Some("session".to_owned()),
            reason: UnableToDecryptReason::Unknown,
        };
        let value = LatestEventValue::Remote(TimelineEvent::from_utd(raw, info));

        assert_eq!(
            summary(&value),
            Some((MessageKindDto::Encrypted, None, false))
        );
    }

    #[test]
    fn message_being_sent_is_own() {
        let content = AnyMessageLikeEventContent::RoomMessage(RoomMessageEventContent::text_plain(
            "enviando",
        ));
        let value = LatestEventValue::LocalIsSending(LocalLatestEventValue {
            timestamp: MilliSecondsSinceUnixEpoch::now(),
            content: SerializableEventContent::new(&content).expect("content"),
        });

        let latest = latest_message(&value, &own_user()).expect("latest message");

        assert_eq!(latest.kind, MessageKindDto::Text);
        assert_eq!(latest.body.as_deref(), Some("enviando"));
        assert_eq!(latest.sender, Some(own_user()));
        assert!(latest.is_own);
    }

    #[test]
    fn no_latest_event_means_no_message() {
        assert_eq!(latest_message(&LatestEventValue::None, &own_user()), None);
    }

    #[test]
    fn preview_is_a_single_trimmed_line() {
        let value = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.text", "body": "  primeira\n\nsegunda   linha " }),
        ));

        assert_eq!(
            summary(&value).and_then(|(_, body, _)| body).as_deref(),
            Some("primeira segunda linha")
        );
    }

    #[test]
    fn long_preview_is_truncated() {
        let body = "a".repeat(PREVIEW_MAX_CHARS + 50);
        let value = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.text", "body": body }),
        ));

        let preview = summary(&value).and_then(|(_, body, _)| body).expect("body");

        assert_eq!(preview.chars().count(), PREVIEW_MAX_CHARS);
    }

    #[test]
    fn last_message_dto_carries_the_sender_name() {
        let value = remote(message(
            "@alice:example.org",
            json!({ "msgtype": "m.text", "body": "oi" }),
        ));
        let latest = latest_message(&value, &own_user()).expect("latest message");

        assert_eq!(
            latest.into_dto(Some("Alice".to_owned())),
            LastMessageDto {
                sender_name: Some("Alice".to_owned()),
                is_own: false,
                kind: MessageKindDto::Text,
                body: Some("oi".to_owned()),
            }
        );
    }

    #[test]
    fn room_name_ignores_only_empty_names() {
        assert_eq!(
            room_name(RoomDisplayName::Named("Geral".to_owned())),
            Some("Geral".to_owned())
        );
        assert_eq!(
            room_name(RoomDisplayName::Calculated("Alice, Bob".to_owned())),
            Some("Alice, Bob".to_owned())
        );
        assert_eq!(
            room_name(RoomDisplayName::EmptyWas("Alice".to_owned())),
            Some("Alice".to_owned())
        );
        assert_eq!(room_name(RoomDisplayName::Empty), None);
    }

    #[test]
    fn initial_skips_matrix_sigils_and_is_uppercase() {
        assert_eq!(room_initial(Some("geral")), "G");
        assert_eq!(room_initial(Some("#rust:matrix.org")), "R");
        assert_eq!(room_initial(Some("@alice:example.org")), "A");
        assert_eq!(room_initial(Some("  équipe")), "É");
    }

    #[test]
    fn initial_keeps_whole_graphemes() {
        assert_eq!(room_initial(Some("🇧🇷 Brasil")), "🇧🇷");
        assert_eq!(room_initial(Some("e\u{301}lan")), "E\u{301}");
    }

    #[test]
    fn initial_falls_back_when_there_is_no_name() {
        assert_eq!(room_initial(None), "#");
        assert_eq!(room_initial(Some("   ")), "#");
        assert_eq!(room_initial(Some("#")), "#");
    }
}
