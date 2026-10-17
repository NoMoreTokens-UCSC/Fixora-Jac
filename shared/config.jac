# Owner: Member A. Import only on the server; never export Settings to the UI.
import os;
import hmac;
import from pathlib { Path }
import from dotenv { dotenv_values }
import from shared.contracts { FixoraError }
import from shared.sessions { _valid_session }

obj Settings {
    has mongodb_uri: str;
    has database_name: str;
    has access_token: str;
    has shop_id: str = "fixora-demo-shop";
    has timezone: str = "Asia/Colombo";
    has model: str = "";
    has demo_mode: bool = False;
    has max_file_bytes: int = 5242880;
    has stage_lease_seconds: int = 120;
}

def _get_settings() -> Settings {
    # Read without exporting values: MONGODB_URI is also a Jac graph-runtime
    # switch, so mutating process env here would change the next Jac context.
    values = dotenv_values(dotenv_path=str(Path.cwd() / ".env"), interpolate=False);
    uri = str(os.getenv("FIXORA_MONGODB_URI") or os.getenv("MONGODB_URI")
        or values.get("FIXORA_MONGODB_URI") or values.get("MONGODB_URI") or "").strip();
    if not uri.startswith(("mongodb://", "mongodb+srv://")) {
        raise FixoraError("CONFIGURATION_ERROR", "Set a valid server-side MONGODB_URI.");
    }
    database_name = _config_value("MONGODB_DB", values, "fixora_dev").strip();
    if not database_name or len(database_name) > 63 or `any(c in database_name for c in '/\\. "$*<>:|?') {
        raise FixoraError("CONFIGURATION_ERROR", "MONGODB_DB is not a valid database name.");
    }
    return Settings(
        mongodb_uri=uri,
        database_name=database_name,
        access_token=_config_value("FIXORA_ACCESS_TOKEN", values, ""),
        timezone=_config_value("FIXORA_SHOP_TIMEZONE", values, "Asia/Colombo"),
        model=_config_value("FIXORA_MODEL", values, ""),
        demo_mode=_config_value("FIXORA_DEMO_MODE", values, "false").lower() == "true"
    );
}

def _config_value(name: str, local_values: dict[str, str | None], fallback: str) -> str {
    process_value = os.getenv(name);
    if process_value is not None { return process_value; }
    return local_values.get(name) or fallback;
}

def _require_access(access_token: str) {
    settings = _get_settings();
    secret = settings.access_token;
    if len(secret) < 16 {
        raise FixoraError("ACCESS_NOT_CONFIGURED", "Configure FIXORA_ACCESS_TOKEN with at least 16 characters on the server.");
    }
    if not hmac.compare_digest(access_token.encode("utf-8"), secret.encode("utf-8"))
        and not _valid_session(secret, settings.shop_id, access_token) {
        raise FixoraError("UNAUTHORIZED", "Sign in again or supply a valid API access token.");
    }
}
