# Shared entrypoint: explicitly register every backend operation and render UI.
# Keep imports of server functions at module scope for Jac's endpoint registry.
# Their contract types are already imported in server/cases and server/evidence;
# redundant type-only imports here trigger incorrect wasm bindings in 0.34.6.
import from server.runtime_compat { _install_runtime_compat }
import from server.cases { create_case, get_case, list_cases, update_case,
    start_assessment, advance_case, platform_status }
import from server.evidence { upload_evidence, get_evidence, remove_evidence }
import from server.auth { demo_login }

with entry { _install_runtime_compat(); }

import from .ui.app { Fixora }
import ".styles.global.css";
import ".ui.styles.css";
import ".ui.login.css";

def:pub app() -> JsxElement { return <Fixora/>; }
