// Runs login, session restore and logout against a real homeserver.
//
// MATRIX_TEST_HOMESERVER=... MATRIX_TEST_USER=... MATRIX_TEST_PASSWORD=... \
//     cargo test --test auth_flow -- --ignored

use std::{env, fs, panic};

use matrix_sdk::{
    authentication::matrix::MatrixSession, config::RequestConfig, ruma::UserId, Client,
    SessionMeta, SessionTokens,
};
use rand::distr::{Alphanumeric, SampleString};
use rust_lib_matrix_client::api::{
    client::MatrixClientHandle,
    session::{LogoutOutcomeDto, SessionDto},
};

struct Credentials {
    homeserver: String,
    user: String,
    password: String,
}

impl Credentials {
    fn from_env() -> Self {
        Self {
            homeserver: required_var("MATRIX_TEST_HOMESERVER"),
            user: required_var("MATRIX_TEST_USER"),
            password: required_var("MATRIX_TEST_PASSWORD"),
        }
    }
}

fn required_var(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| panic!("{name} must be set to run this test"))
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a homeserver and MATRIX_TEST_HOMESERVER, MATRIX_TEST_USER, MATRIX_TEST_PASSWORD"]
async fn login_restore_and_logout() {
    let credentials = Credentials::from_env();
    let data_dir = tempfile::tempdir().expect("temporary directory");
    let data_dir_path = data_dir.path().to_string_lossy().into_owned();
    let passphrase = Alphanumeric.sample_string(&mut rand::rng(), 32);

    // Loopback http is allowed so the test also runs against a local homeserver.
    // The handle is dropped right after login, like an app that is closed and reopened.
    let session = MatrixClientHandle::new(true)
        .login(
            credentials.homeserver,
            credentials.user,
            credentials.password,
            data_dir_path.clone(),
            passphrase.clone(),
        )
        .await
        .expect("login failed");

    // The remaining steps run in their own task so that a failed assertion still
    // lets the device be revoked on the server below.
    let outcome = tokio::spawn(restore_and_logout(
        session.clone(),
        data_dir_path,
        passphrase,
    ))
    .await;
    revoke_on_server(&session).await;

    if let Err(error) = outcome {
        if error.is_panic() {
            panic::resume_unwind(error.into_panic());
        }
        panic!("test task did not finish: {error}");
    }
}

async fn restore_and_logout(session: SessionDto, data_dir: String, passphrase: String) {
    assert!(
        session.user_id.starts_with('@'),
        "unexpected user id {}",
        session.user_id
    );
    assert!(!session.device_id.is_empty(), "missing device id");
    assert!(!session.access_token.is_empty(), "missing access token");

    let handle = MatrixClientHandle::new(true);
    handle
        .restore_session(session.clone(), data_dir.clone(), passphrase)
        .await
        .expect("restore failed");
    assert_eq!(
        handle.logout().await,
        Ok(LogoutOutcomeDto::Complete),
        "logout should reach the server"
    );

    let mut entries = fs::read_dir(&data_dir).expect("read data directory");
    assert!(
        entries.next().is_none(),
        "logout should leave the data directory empty"
    );
    assert!(
        !token_is_valid(&session).await,
        "logout should revoke the access token"
    );
}

// A client independent from the code under test, with an in-memory store.
async fn sdk_client(session: &SessionDto) -> Result<Client, String> {
    let client = Client::builder()
        .homeserver_url(&session.homeserver)
        .request_config(RequestConfig::short_retry())
        .build()
        .await
        .map_err(|error| error.to_string())?;
    let user_id = UserId::parse(&session.user_id).map_err(|error| error.to_string())?;
    client
        .restore_session(MatrixSession {
            meta: SessionMeta {
                user_id,
                device_id: session.device_id.as_str().into(),
            },
            tokens: SessionTokens {
                access_token: session.access_token.clone(),
                refresh_token: None,
            },
        })
        .await
        .map_err(|error| error.to_string())?;
    Ok(client)
}

async fn token_is_valid(session: &SessionDto) -> bool {
    let client = sdk_client(session).await.expect("verification client");
    match client.whoami().await {
        Ok(_) => true,
        Err(error) if is_unauthorized(error.as_client_api_error()) => false,
        Err(error) => panic!("could not check the access token: {error}"),
    }
}

// Safe to call after a successful logout: the revoked token just gets a 401.
async fn revoke_on_server(session: &SessionDto) {
    let client = match sdk_client(session).await {
        Ok(client) => client,
        Err(error) => {
            eprintln!("cleanup: could not revoke the test device: {error}");
            return;
        }
    };
    match client.logout().await {
        Ok(()) => {}
        Err(error) if is_unauthorized(error.as_client_api_error()) => {}
        Err(error) => eprintln!("cleanup: could not revoke the test device: {error}"),
    }
}

fn is_unauthorized(error: Option<&matrix_sdk::ruma::api::error::Error>) -> bool {
    error.is_some_and(|error| error.status_code.as_u16() == 401)
}
