use std::{path::Path, time::Duration};

use matrix_sdk::{
    authentication::matrix::MatrixSession,
    config::RequestConfig,
    ruma::{api::client::account::whoami, UserId},
    sliding_sync::VersionBuilder as SlidingSyncVersionBuilder,
    Client, ClientBuilder, SessionMeta, SessionTokens,
};
use tracing::{info, warn};

use crate::{
    api::{
        error::MatrixError,
        session::{LogoutOutcomeDto, SessionDto},
    },
    matrix::{
        errors,
        homeserver::{check_homeserver_url, parse_homeserver_url, HomeserverInput},
        store::Store,
    },
};

const DEVICE_DISPLAY_NAME: &str = "Matrix Desktop Client";
const SESSION_CHECK_TIMEOUT: Duration = Duration::from_secs(10);

pub(crate) async fn login(
    homeserver: HomeserverInput,
    username: &str,
    password: &str,
    store: &Store,
    passphrase: &str,
    allow_insecure_localhost: bool,
) -> Result<(Client, SessionDto), MatrixError> {
    let builder = match homeserver {
        HomeserverInput::Url(url) => Client::builder().homeserver_url(url),
        HomeserverInput::ServerName(name) => Client::builder().server_name_or_homeserver_url(name),
    };
    let client = build_client(builder, &store.path, passphrase).await?;

    let homeserver = client.homeserver();
    if let Err(error) = check_homeserver_url(&homeserver, allow_insecure_localhost) {
        warn!(%homeserver, "Discovered homeserver is not allowed");
        return Err(error);
    }
    ensure_sliding_sync(&client).await?;

    let response = client
        .matrix_auth()
        .login_username(username, password)
        .initial_device_display_name(DEVICE_DISPLAY_NAME)
        .send()
        .await
        .map_err(|error| {
            warn!(%error, "Login failed");
            errors::from_login_error(&error)
        })?;

    info!(user_id = %response.user_id, "Logged in");
    let session = SessionDto {
        homeserver: homeserver.to_string(),
        user_id: response.user_id.to_string(),
        device_id: response.device_id.to_string(),
        access_token: response.access_token,
        store_id: store.id.clone(),
    };
    Ok((client, session))
}

pub(crate) async fn restore(
    session: SessionDto,
    store_path: &Path,
    passphrase: &str,
    allow_insecure_localhost: bool,
) -> Result<Client, MatrixError> {
    let homeserver = parse_homeserver_url(&session.homeserver, allow_insecure_localhost)?;
    let user_id = UserId::parse(&session.user_id).map_err(|error| {
        warn!(%error, "Stored user id is invalid");
        MatrixError::Storage
    })?;
    let client = build_client(
        Client::builder().homeserver_url(homeserver),
        store_path,
        passphrase,
    )
    .await?;

    let matrix_session = MatrixSession {
        meta: SessionMeta {
            user_id,
            device_id: session.device_id.into(),
        },
        tokens: SessionTokens {
            access_token: session.access_token,
            refresh_token: None,
        },
    };
    client
        .restore_session(matrix_session)
        .await
        .map_err(|error| {
            warn!(%error, "Could not restore the session");
            errors::from_sdk_error(&error)
        })?;

    info!(user_id = %session.user_id, "Session restored");
    Ok(client)
}

// Only a rejected token ends the session. Any other failure keeps it restored so
// that the app still opens offline.
pub(crate) async fn check_session(client: &Client) -> Result<(), MatrixError> {
    let config = RequestConfig::new()
        .disable_retry()
        .timeout(SESSION_CHECK_TIMEOUT);
    let Err(error) = client
        .send(whoami::v3::Request::new())
        .with_request_config(config)
        .await
    else {
        return Ok(());
    };

    if errors::from_http_error(&error) == MatrixError::SessionExpired {
        info!("Stored session was rejected by the homeserver");
        return Err(MatrixError::SessionExpired);
    }
    warn!(%error, "Could not check the session, keeping it restored");
    Ok(())
}

pub(crate) async fn logout(client: &Client) -> LogoutOutcomeDto {
    match client.logout().await {
        Ok(()) => {
            info!("Logged out");
            LogoutOutcomeDto::Complete
        }
        Err(error) if errors::from_sdk_error(&error) == MatrixError::SessionExpired => {
            info!("Session was already invalid on the homeserver");
            LogoutOutcomeDto::Complete
        }
        Err(error) => {
            warn!(%error, "Server logout failed, clearing local data anyway");
            LogoutOutcomeDto::LocalOnly
        }
    }
}

// The room list relies on sliding sync (MSC4186). Checking it before logging in avoids
// creating a device on a homeserver the app could never sync with.
async fn ensure_sliding_sync(client: &Client) -> Result<(), MatrixError> {
    let supported = client.supported_versions().await.map_err(|error| {
        warn!(%error, "Could not read the homeserver versions");
        match errors::from_http_error(&error) {
            MatrixError::Network => MatrixError::Network,
            _ => MatrixError::InvalidHomeserver,
        }
    })?;
    if SlidingSyncVersionBuilder::DiscoverNative
        .build(Some(&supported))
        .is_err()
    {
        warn!("Homeserver does not support sliding sync");
        return Err(MatrixError::UnsupportedHomeserver);
    }
    Ok(())
}

async fn build_client(
    builder: ClientBuilder,
    store_path: &Path,
    passphrase: &str,
) -> Result<Client, MatrixError> {
    builder
        .sqlite_store(store_path, Some(passphrase))
        .respect_login_well_known(false)
        // The SDK default retries failed requests for up to 15 minutes.
        .request_config(RequestConfig::short_retry())
        .build()
        .await
        .map_err(|error| {
            warn!(%error, "Could not build the client");
            errors::from_build_error(&error)
        })
}
