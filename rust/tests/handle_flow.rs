// Runs the MatrixClientHandle session lifecycle against a local mock homeserver.

use std::{fs, time::Duration};

use rust_lib_matrix_client::api::{
    client::MatrixClientHandle,
    error::MatrixError,
    session::{LogoutOutcomeDto, SessionDto},
};
use serde_json::json;
use tempfile::TempDir;
use wiremock::{
    matchers::{body_partial_json, method, path, path_regex},
    Mock, MockServer, ResponseTemplate,
};

const USER_ID: &str = "@alice:example.org";
const MOCK_PASSWORD: &str = "mock-password";

// A dedicated server instead of the pooled `MockServer::start()`, so that dropping it
// really closes the port and the unreachable-server tests are meaningful.
async fn homeserver() -> MockServer {
    let server = homeserver_without_sliding_sync().await;
    Mock::given(method("GET"))
        .and(path("/_matrix/client/versions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "versions": ["v1.11"],
            "unstable_features": { "org.matrix.simplified_msc3575": true },
        })))
        .with_priority(1)
        .mount(&server)
        .await;
    // Answers like an idle long poll, so the sync started after login stays quiet.
    Mock::given(method("POST"))
        .and(path_regex("simplified_msc3575/sync$"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "pos": "0" }))
                .set_delay(Duration::from_secs(30)),
        )
        .mount(&server)
        .await;
    server
}

async fn homeserver_without_sliding_sync() -> MockServer {
    let server = MockServer::builder().start().await;
    Mock::given(method("GET"))
        .and(path("/_matrix/client/versions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "versions": ["v1.11"] })))
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/login"))
        .and(body_partial_json(json!({ "password": MOCK_PASSWORD })))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "user_id": USER_ID,
            "access_token": "mock-access-token",
            "device_id": "MOCKDEVICE",
        })))
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/login"))
        .respond_with(ResponseTemplate::new(403).set_body_json(json!({
            "errcode": "M_FORBIDDEN",
            "error": "Invalid username or password",
        })))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/_matrix/client/v3/account/whoami"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "user_id": USER_ID,
            "device_id": "MOCKDEVICE",
        })))
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/logout"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
        .mount(&server)
        .await;
    server
}

fn data_dir() -> TempDir {
    tempfile::tempdir().expect("temporary directory")
}

fn dir_path(dir: &TempDir) -> String {
    dir.path().to_string_lossy().into_owned()
}

fn store_ids(dir: &TempDir) -> Vec<String> {
    let Ok(entries) = fs::read_dir(dir.path().join("stores")) else {
        return Vec::new();
    };
    let mut ids: Vec<String> = entries
        .map(|entry| {
            entry
                .expect("store entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    ids.sort();
    ids
}

async fn login(
    handle: &MatrixClientHandle,
    server: &MockServer,
    dir: &TempDir,
    password: &str,
    passphrase: &str,
) -> Result<SessionDto, MatrixError> {
    handle
        .login(
            server.uri(),
            "alice".to_owned(),
            password.to_owned(),
            dir_path(dir),
            passphrase.to_owned(),
        )
        .await
}

#[tokio::test(flavor = "multi_thread")]
async fn same_handle_logs_in_again_after_logout() {
    let server = homeserver().await;
    let dir = data_dir();
    let handle = MatrixClientHandle::new(true);

    let first = login(&handle, &server, &dir, MOCK_PASSWORD, "first-passphrase")
        .await
        .expect("first login");
    assert_eq!(handle.logout().await, Ok(LogoutOutcomeDto::Complete));
    assert!(store_ids(&dir).is_empty());

    let second = login(&handle, &server, &dir, MOCK_PASSWORD, "second-passphrase")
        .await
        .expect("second login");

    assert_ne!(first.store_id, second.store_id);
    assert_eq!(store_ids(&dir), vec![second.store_id]);
}

#[tokio::test(flavor = "multi_thread")]
async fn login_starts_with_a_new_store_and_drops_the_previous_one() {
    let server = homeserver().await;
    let dir = data_dir();
    let handle = MatrixClientHandle::new(true);

    let first = login(&handle, &server, &dir, MOCK_PASSWORD, "first-passphrase")
        .await
        .expect("first login");
    // A different passphrase only works if the previous store is not reused.
    let second = login(&handle, &server, &dir, MOCK_PASSWORD, "second-passphrase")
        .await
        .expect("second login");

    assert_ne!(first.store_id, second.store_id);
    assert_eq!(store_ids(&dir), vec![second.store_id]);
}

#[tokio::test(flavor = "multi_thread")]
async fn failed_login_keeps_the_saved_session_restorable() {
    let server = homeserver().await;
    let dir = data_dir();
    let saved = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "saved-passphrase",
    )
    .await
    .expect("login");

    let handle = MatrixClientHandle::new(true);
    let failed = login(&handle, &server, &dir, "wrong-password", "other-passphrase").await;

    assert_eq!(failed.err(), Some(MatrixError::InvalidCredentials));
    assert_eq!(store_ids(&dir), vec![saved.store_id.clone()]);
    handle
        .restore_session(saved, dir_path(&dir), "saved-passphrase".to_owned())
        .await
        .expect("restore after failed login");
}

#[tokio::test(flavor = "multi_thread")]
async fn restore_uses_the_saved_homeserver_without_discovery() {
    let server = homeserver().await;
    Mock::given(path("/.well-known/matrix/client"))
        .respond_with(ResponseTemplate::new(404))
        .expect(0)
        .mount(&server)
        .await;
    let dir = data_dir();
    let session = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "passphrase",
    )
    .await
    .expect("login");

    MatrixClientHandle::new(true)
        .restore_session(session, dir_path(&dir), "passphrase".to_owned())
        .await
        .expect("restore");

    server.verify().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn restore_keeps_the_session_when_the_server_is_unreachable() {
    let server = homeserver().await;
    let dir = data_dir();
    let session = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "passphrase",
    )
    .await
    .expect("login");
    drop(server);

    MatrixClientHandle::new(true)
        .restore_session(session.clone(), dir_path(&dir), "passphrase".to_owned())
        .await
        .expect("offline restore");

    assert_eq!(store_ids(&dir), vec![session.store_id]);
}

#[tokio::test(flavor = "multi_thread")]
async fn restore_with_a_rejected_token_removes_the_store() {
    let server = homeserver().await;
    let dir = data_dir();
    let session = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "passphrase",
    )
    .await
    .expect("login");
    Mock::given(method("GET"))
        .and(path("/_matrix/client/v3/account/whoami"))
        .respond_with(ResponseTemplate::new(401).set_body_json(json!({
            "errcode": "M_UNKNOWN_TOKEN",
            "error": "Invalid access token",
        })))
        .with_priority(1)
        .mount(&server)
        .await;

    let result = MatrixClientHandle::new(true)
        .restore_session(session, dir_path(&dir), "passphrase".to_owned())
        .await;

    assert_eq!(result, Err(MatrixError::SessionExpired));
    assert!(store_ids(&dir).is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn restore_rejects_a_store_id_outside_the_stores_directory() {
    let server = homeserver().await;
    let dir = data_dir();
    let mut session = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "passphrase",
    )
    .await
    .expect("login");
    session.store_id = "../stores".to_owned();

    let result = MatrixClientHandle::new(true)
        .restore_session(session, dir_path(&dir), "passphrase".to_owned())
        .await;

    assert_eq!(result, Err(MatrixError::Storage));
}

#[tokio::test(flavor = "multi_thread")]
async fn logout_without_the_server_is_local_only() {
    let server = homeserver().await;
    let dir = data_dir();
    let handle = MatrixClientHandle::new(true);
    login(&handle, &server, &dir, MOCK_PASSWORD, "passphrase")
        .await
        .expect("login");
    drop(server);

    assert_eq!(handle.logout().await, Ok(LogoutOutcomeDto::LocalOnly));
    assert!(store_ids(&dir).is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn login_rejects_a_server_without_sliding_sync() {
    let server = homeserver_without_sliding_sync().await;
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/login"))
        .respond_with(ResponseTemplate::new(403))
        .expect(0)
        .named("login")
        .mount(&server)
        .await;
    let dir = data_dir();

    let result = login(
        &MatrixClientHandle::new(true),
        &server,
        &dir,
        MOCK_PASSWORD,
        "passphrase",
    )
    .await;

    assert_eq!(result.err(), Some(MatrixError::UnsupportedHomeserver));
    assert!(store_ids(&dir).is_empty());
    server.verify().await;
}
