use matrix_sdk::{
    ruma::api::{
        client::uiaa::UiaaResponse,
        error::{ErrorKind, FromHttpResponseError},
    },
    ClientBuildError, Error, HttpError,
};

use crate::api::error::MatrixError;

pub(crate) fn from_sdk_error(error: &Error) -> MatrixError {
    match error {
        Error::Http(error) => from_http_error(error),
        Error::Io(_)
        | Error::StateStore(_)
        | Error::CryptoStoreError(_)
        | Error::EventCacheStore(_)
        | Error::MediaStore(_) => MatrixError::Storage,
        _ => MatrixError::Unknown,
    }
}

pub(crate) fn from_http_error(error: &HttpError) -> MatrixError {
    match error {
        HttpError::Reqwest(_) => MatrixError::Network,
        HttpError::Cached(inner) => from_http_error(inner),
        _ => match error.as_client_api_error() {
            Some(api_error) => {
                from_api_error(api_error.status_code.as_u16(), api_error.error_kind())
            }
            None => MatrixError::Unknown,
        },
    }
}

pub(crate) fn from_api_error(status: u16, kind: Option<&ErrorKind>) -> MatrixError {
    if status == 401 || matches!(kind, Some(ErrorKind::UnknownToken(_))) {
        MatrixError::SessionExpired
    } else {
        MatrixError::Unknown
    }
}

pub(crate) fn from_login_error(error: &Error) -> MatrixError {
    match error {
        Error::Http(error) => from_login_http_error(error),
        _ => from_sdk_error(error),
    }
}

fn from_login_http_error(error: &HttpError) -> MatrixError {
    match error {
        HttpError::Reqwest(_) => MatrixError::Network,
        HttpError::Cached(inner) => from_login_http_error(inner),
        HttpError::Api(api_error) => match api_error.as_ref() {
            FromHttpResponseError::Server(UiaaResponse::MatrixError(error)) => {
                from_login_api_error(error.status_code.as_u16(), error.error_kind())
            }
            // A success status with a body that is not a login response.
            FromHttpResponseError::Deserialization(_) => MatrixError::InvalidHomeserver,
            _ => MatrixError::Unknown,
        },
        _ => MatrixError::Unknown,
    }
}

pub(crate) fn from_login_api_error(status: u16, kind: Option<&ErrorKind>) -> MatrixError {
    match kind {
        Some(ErrorKind::Forbidden | ErrorKind::UserDeactivated) => MatrixError::InvalidCredentials,
        Some(ErrorKind::Unrecognized) => MatrixError::InvalidHomeserver,
        Some(_) => MatrixError::Unknown,
        // Without a Matrix error body the response came from something other than a
        // homeserver: a proxy in front of a server that is down, or a regular website.
        None if status >= 500 => MatrixError::Network,
        None => MatrixError::InvalidHomeserver,
    }
}

pub(crate) fn from_build_error(error: &ClientBuildError) -> MatrixError {
    match error {
        ClientBuildError::Http(error) if from_http_error(error) == MatrixError::Network => {
            MatrixError::Network
        }
        ClientBuildError::SqliteStore(_) => MatrixError::Storage,
        ClientBuildError::Http(_)
        | ClientBuildError::AutoDiscovery(_)
        | ClientBuildError::InvalidServerName
        | ClientBuildError::MissingHomeserver
        | ClientBuildError::Url(_) => MatrixError::InvalidHomeserver,
        _ => MatrixError::Unknown,
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::{
        api::error::{
            Error as RumaError, ErrorBody, LimitExceededErrorData, StandardErrorBody,
            UnknownTokenErrorData,
        },
        exports::http::StatusCode,
    };

    use super::*;

    fn api_error(status: StatusCode, kind: ErrorKind) -> HttpError {
        let body = ErrorBody::Standard(StandardErrorBody::new(kind, String::new()));
        let response = UiaaResponse::MatrixError(RumaError::new(status, body));
        HttpError::Api(Box::new(FromHttpResponseError::Server(response)))
    }

    #[test]
    fn unknown_token_means_session_expired() {
        let kind = ErrorKind::UnknownToken(UnknownTokenErrorData::new());
        assert_eq!(
            from_api_error(401, Some(&kind)),
            MatrixError::SessionExpired
        );
    }

    #[test]
    fn unauthorized_status_means_session_expired() {
        assert_eq!(from_api_error(401, None), MatrixError::SessionExpired);
        assert_eq!(
            from_api_error(401, Some(&ErrorKind::MissingToken)),
            MatrixError::SessionExpired
        );
    }

    #[test]
    fn other_api_errors_do_not_expire_the_session() {
        assert_eq!(
            from_api_error(403, Some(&ErrorKind::Forbidden)),
            MatrixError::Unknown
        );
        assert_eq!(from_api_error(500, None), MatrixError::Unknown);
    }

    #[test]
    fn http_error_with_unknown_token_means_session_expired() {
        let error = api_error(
            StatusCode::UNAUTHORIZED,
            ErrorKind::UnknownToken(UnknownTokenErrorData::new()),
        );
        assert_eq!(from_http_error(&error), MatrixError::SessionExpired);
    }

    #[test]
    fn forbidden_login_means_invalid_credentials() {
        assert_eq!(
            from_login_api_error(403, Some(&ErrorKind::Forbidden)),
            MatrixError::InvalidCredentials
        );
        assert_eq!(
            from_login_api_error(403, Some(&ErrorKind::UserDeactivated)),
            MatrixError::InvalidCredentials
        );
    }

    #[test]
    fn login_error_is_mapped_through_the_sdk_error() {
        let error = Error::Http(Box::new(api_error(
            StatusCode::FORBIDDEN,
            ErrorKind::Forbidden,
        )));
        assert_eq!(from_login_error(&error), MatrixError::InvalidCredentials);
    }

    #[test]
    fn login_without_matrix_error_body_means_invalid_homeserver() {
        assert_eq!(
            from_login_api_error(404, None),
            MatrixError::InvalidHomeserver
        );
        assert_eq!(
            from_login_api_error(404, Some(&ErrorKind::Unrecognized)),
            MatrixError::InvalidHomeserver
        );
    }

    #[test]
    fn login_server_failure_without_matrix_body_means_network() {
        assert_eq!(from_login_api_error(502, None), MatrixError::Network);
    }

    #[test]
    fn other_login_errors_are_unknown() {
        let kind = ErrorKind::LimitExceeded(LimitExceededErrorData::new());
        assert_eq!(from_login_api_error(429, Some(&kind)), MatrixError::Unknown);
    }

    #[test]
    fn invalid_server_name_means_invalid_homeserver() {
        assert_eq!(
            from_build_error(&ClientBuildError::InvalidServerName),
            MatrixError::InvalidHomeserver
        );
    }
}
