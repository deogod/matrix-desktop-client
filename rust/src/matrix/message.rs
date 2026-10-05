use matrix_sdk::ruma::events::room::message::MessageType;

use crate::api::room::MessageKindDto;

// Media only reports its kind: there is no media support yet, so its body (usually a
// file name) is not shown.
pub(crate) fn message_summary(message: &MessageType) -> (MessageKindDto, Option<&str>) {
    match message {
        MessageType::Text(content) => (MessageKindDto::Text, Some(&content.body)),
        MessageType::Emote(content) => (MessageKindDto::Emote, Some(&content.body)),
        MessageType::Notice(content) => (MessageKindDto::Notice, Some(&content.body)),
        MessageType::Image(_) => (MessageKindDto::Image, None),
        MessageType::Video(_) => (MessageKindDto::Video, None),
        MessageType::Audio(_) => (MessageKindDto::Audio, None),
        MessageType::File(_) => (MessageKindDto::File, None),
        MessageType::Location(_) => (MessageKindDto::Location, None),
        other => (MessageKindDto::Other, Some(other.body())),
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::events::room::message::{
        EmoteMessageEventContent, NoticeMessageEventContent, TextMessageEventContent,
    };

    use super::*;

    #[test]
    fn text_like_messages_keep_their_body() {
        let text = MessageType::Text(TextMessageEventContent::plain("oi\ntudo bem?"));
        let emote = MessageType::Emote(EmoteMessageEventContent::plain("acena"));
        let notice = MessageType::Notice(NoticeMessageEventContent::plain("aviso"));

        assert_eq!(
            message_summary(&text),
            (MessageKindDto::Text, Some("oi\ntudo bem?"))
        );
        assert_eq!(
            message_summary(&emote),
            (MessageKindDto::Emote, Some("acena"))
        );
        assert_eq!(
            message_summary(&notice),
            (MessageKindDto::Notice, Some("aviso"))
        );
    }
}
