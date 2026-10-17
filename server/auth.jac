# Hackathon demo login: server-checked public accounts, shared single-shop access.
import hmac;
import logging;
import from shared.config { _get_settings, _require_access }
import from shared.contracts { ApiResult, FixoraError, _success, _failure }
import from shared.sessions { _issue_session }

def:pub demo_login(email: str, password: str, role: str) -> ApiResult {
    try {
        settings = _get_settings();
        # Fail closed when the private signing/access secret is missing or short.
        _require_access(settings.access_token);
        expected = "owner@fixora.demo" if role == "owner" else "customer@fixora.demo";
        if role not in ["customer", "owner"] or len(email) > 254 or len(password) > 1024
            or not hmac.compare_digest(email.strip().lower().encode("utf-8"), expected.encode("utf-8"))
            or not hmac.compare_digest(password.encode("utf-8"), b"Fixora123!") {
            return _failure("INVALID_CREDENTIALS", "These details do not match the selected demo account.");
        }
        return _success(_issue_session(settings.access_token, settings.shop_id, role));
    } except FixoraError as error { return _failure(error.code, error.message); }
    except Exception as error {
        logging.getLogger("fixora").error("Demo login failed (%s)", type(error).__name__);
        return _failure("LOGIN_UNAVAILABLE", "Sign-in is temporarily unavailable. Check the server configuration.");
    }
}
