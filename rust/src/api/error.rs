// Without fields so that flutter_rust_bridge generates a plain Dart enum.
// Error details are logged on the Rust side.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatrixError {
    InvalidCredentials,
    InvalidHomeserver,
    Network,
    SessionExpired,
    Storage,
    // The homeserver does not offer the sliding sync (MSC4186) the room list relies on.
    UnsupportedHomeserver,
    Unknown,
}
