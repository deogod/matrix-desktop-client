use tracing_subscriber::EnvFilter;

const DEFAULT_LOG_FILTER: &str = "warn,rust_lib_matrix_client=info";

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_backtrace();
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(DEFAULT_LOG_FILTER));
    // Hot restart runs init again, and the global subscriber can only be set once.
    let _ = tracing_subscriber::fmt().with_env_filter(filter).try_init();
}
