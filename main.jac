# Jac API and private owner UI composition (shared runtime 0.34.13).
# Keep service operations explicitly imported for endpoint registration.
import from server.runtime_compat { _install_runtime_compat }
import from server.cases { create_case, get_case, list_cases, update_case,
    start_assessment, advance_case, platform_status }
import from server.evidence { upload_evidence, get_evidence, remove_evidence }
import from server.owner { owner_message, owner_review, owner_inspection }

with entry { _install_runtime_compat(); }

# Customer intake is exclusively through the WhatsApp adapter.
import from .ui.app { Fixora }
import ".styles.global.css";
import ".ui.styles.css";
import ".ui.login.css";
import ".ui.readability.css";
import ".ui.login-feature.css";

def:pub app() -> JsxElement { return <Fixora/>; }
