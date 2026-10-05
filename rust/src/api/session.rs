use std::fmt;

#[derive(Clone, PartialEq, Eq)]
pub struct SessionDto {
    pub homeserver: String,
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
    pub store_id: String,
}

impl fmt::Debug for SessionDto {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SessionDto")
            .field("homeserver", &self.homeserver)
            .field("user_id", &self.user_id)
            .field("device_id", &self.device_id)
            .field("store_id", &self.store_id)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogoutOutcomeDto {
    Complete,
    // Local data was removed, but the homeserver could not be told to revoke the token.
    LocalOnly,
}
