use std::net::{Ipv4Addr, Ipv6Addr};

use matrix_sdk::ruma::{OwnedServerName, ServerName};
use url::{Host, Url};

use crate::api::error::MatrixError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum HomeserverInput {
    Url(Url),
    ServerName(OwnedServerName),
}

pub(crate) fn parse_homeserver_input(
    input: &str,
    allow_insecure_localhost: bool,
) -> Result<HomeserverInput, MatrixError> {
    let input = input.trim();
    if input.is_empty() {
        return Err(MatrixError::InvalidHomeserver);
    }
    if input.contains("://") {
        return parse_homeserver_url(input, allow_insecure_localhost).map(HomeserverInput::Url);
    }
    if let Ok(server_name) = ServerName::parse(input) {
        return Ok(HomeserverInput::ServerName(server_name));
    }
    parse_homeserver_url(&format!("https://{input}"), allow_insecure_localhost)
        .map(HomeserverInput::Url)
}

pub(crate) fn parse_homeserver_url(
    input: &str,
    allow_insecure_localhost: bool,
) -> Result<Url, MatrixError> {
    let url = Url::parse(input.trim()).map_err(|_| MatrixError::InvalidHomeserver)?;
    check_homeserver_url(&url, allow_insecure_localhost)?;
    Ok(url)
}

pub(crate) fn check_homeserver_url(
    url: &Url,
    allow_insecure_localhost: bool,
) -> Result<(), MatrixError> {
    if url.host().is_none() || !url.username().is_empty() || url.password().is_some() {
        return Err(MatrixError::InvalidHomeserver);
    }
    let allowed = match url.scheme() {
        "https" => true,
        "http" => allow_insecure_localhost && is_loopback(url),
        _ => false,
    };
    if allowed {
        Ok(())
    } else {
        Err(MatrixError::InvalidHomeserver)
    }
}

fn is_loopback(url: &Url) -> bool {
    match url.host() {
        Some(Host::Domain(domain)) => domain == "localhost",
        Some(Host::Ipv4(address)) => address == Ipv4Addr::LOCALHOST,
        Some(Host::Ipv6(address)) => address == Ipv6Addr::LOCALHOST,
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url_input(url: &str) -> HomeserverInput {
        HomeserverInput::Url(Url::parse(url).expect("valid test url"))
    }

    fn server_name_input(name: &str) -> HomeserverInput {
        HomeserverInput::ServerName(ServerName::parse(name).expect("valid test server name"))
    }

    #[test]
    fn accepts_https_url() {
        assert_eq!(
            parse_homeserver_input("https://matrix-client.matrix.org", false),
            Ok(url_input("https://matrix-client.matrix.org"))
        );
    }

    #[test]
    fn keeps_path_of_https_url() {
        assert_eq!(
            parse_homeserver_input("https://example.org/matrix", false),
            Ok(url_input("https://example.org/matrix"))
        );
    }

    #[test]
    fn treats_bare_host_as_server_name() {
        assert_eq!(
            parse_homeserver_input("matrix.org", false),
            Ok(server_name_input("matrix.org"))
        );
    }

    #[test]
    fn treats_host_with_port_as_server_name() {
        assert_eq!(
            parse_homeserver_input("matrix.example.org:8448", false),
            Ok(server_name_input("matrix.example.org:8448"))
        );
    }

    #[test]
    fn prefixes_https_for_address_without_scheme() {
        assert_eq!(
            parse_homeserver_input("example.org/matrix", false),
            Ok(url_input("https://example.org/matrix"))
        );
    }

    #[test]
    fn trims_surrounding_whitespace() {
        assert_eq!(
            parse_homeserver_input("  matrix.org \n", false),
            Ok(server_name_input("matrix.org"))
        );
    }

    #[test]
    fn rejects_empty_input() {
        assert_eq!(
            parse_homeserver_input("   ", true),
            Err(MatrixError::InvalidHomeserver)
        );
    }

    #[test]
    fn rejects_http_for_remote_host_even_when_insecure_is_allowed() {
        assert_eq!(
            parse_homeserver_input("http://matrix.org", true),
            Err(MatrixError::InvalidHomeserver)
        );
    }

    #[test]
    fn accepts_http_loopback_only_when_insecure_is_allowed() {
        for url in [
            "http://localhost:8008",
            "http://127.0.0.1:8008",
            "http://[::1]:8008",
        ] {
            assert_eq!(parse_homeserver_input(url, true), Ok(url_input(url)));
            assert_eq!(
                parse_homeserver_input(url, false),
                Err(MatrixError::InvalidHomeserver)
            );
        }
    }

    #[test]
    fn rejects_http_for_other_loopback_addresses() {
        assert_eq!(
            parse_homeserver_input("http://127.0.0.2:8008", true),
            Err(MatrixError::InvalidHomeserver)
        );
    }

    #[test]
    fn rejects_other_schemes() {
        for url in ["ftp://matrix.org", "ws://localhost:8008", "file:///tmp"] {
            assert_eq!(
                parse_homeserver_input(url, true),
                Err(MatrixError::InvalidHomeserver)
            );
        }
    }

    #[test]
    fn rejects_credentials_in_url() {
        for input in ["https://user:secret@matrix.org", "user@matrix.org"] {
            assert_eq!(
                parse_homeserver_input(input, false),
                Err(MatrixError::InvalidHomeserver)
            );
        }
    }

    #[test]
    fn rejects_malformed_input() {
        for input in ["https://", "://matrix.org", "matrix org"] {
            assert_eq!(
                parse_homeserver_input(input, false),
                Err(MatrixError::InvalidHomeserver)
            );
        }
    }

    #[test]
    fn rejects_discovered_http_homeserver() {
        let discovered = Url::parse("http://matrix.example.org").expect("valid test url");
        assert_eq!(
            check_homeserver_url(&discovered, true),
            Err(MatrixError::InvalidHomeserver)
        );
    }
}
