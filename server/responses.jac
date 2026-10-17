# Owner: Member A. Safe application envelope INSIDE Jac's transport envelope.
import logging;
import from pymongo.errors { PyMongoError }
import from gridfs.errors { NoFile }
import from shared.config { _require_access }
import from shared.contracts { ApiResult, FixoraError, _success, _failure }

def _api_call(access_token: str, operation: Callable[..., dict[str, any]], arguments: list[any] = []) -> ApiResult {
    try {
        _require_access(access_token);
        return _success(operation(*arguments));
    } except FixoraError as error {
        return _failure(error.code, error.message);
    } except PyMongoError {
        return _failure("DATABASE_UNAVAILABLE", "Database operation failed. Retry shortly or check server connectivity.");
    } except NoFile {
        return _failure("EVIDENCE_UNAVAILABLE", "The stored evidence file is not available.");
    } except Exception as error {
        # Deliberately omit exception messages/tracebacks: they can contain URIs.
        logging.getLogger("fixora").error("Platform operation failed (%s)", type(error).__name__);
        return _failure("INTERNAL_ERROR", "The operation could not be completed. Check the server configuration.");
    }
}
