#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomDto {
    pub id: String,
    pub name: Option<String>,
    pub initial: String,
    pub last_message: Option<LastMessageDto>,
    pub last_activity_ms: Option<i64>,
    pub unread_count: u32,
    pub unread_mentions: u32,
    pub is_direct: bool,
}

// Structured instead of a ready-made sentence, so that the wording stays in the UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LastMessageDto {
    pub sender_name: Option<String>,
    pub is_own: bool,
    pub kind: MessageKindDto,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageKindDto {
    Text,
    Emote,
    Notice,
    Image,
    Video,
    Audio,
    File,
    Location,
    Sticker,
    Encrypted,
    Redacted,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncStateDto {
    Syncing,
    Connected,
    Offline,
    SessionExpired,
}
