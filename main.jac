# Owner: Member A. API-only entrypoint until Member C supplies the client app.
# Keep every endpoint explicitly imported here for Jac 0.34.6 registration.
import from shared.contracts { ApiResult, ErrorInfo }
import from server.runtime_compat { _install_runtime_compat }
import from server.cases { create_case, get_case, list_cases, update_case,
    start_assessment, advance_case, platform_status }
import from server.evidence { upload_evidence, get_evidence, remove_evidence }

with entry { _install_runtime_compat(); }

# Member C: export a client app from ui/app.jac, then coordinate adding the
# client import/app wrapper here. Start the current backend with --no-client.
import from .ui.app { Fixora }
import ".styles.global.css";
import ".ui.styles.css";
import ".ui.login.css";
import ".ui.readability.css";
import ".ui.login-feature.css";

def:pub app() -> JsxElement { return <Fixora/>; }
