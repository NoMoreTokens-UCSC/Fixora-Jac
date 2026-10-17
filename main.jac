import from .ui.app { Fixora }
import ".styles.global.css";
import ".ui.styles.css";
import ".ui.login.css";
import ".ui.readability.css";
import ".ui.login-feature.css";

def:pub app() -> JsxElement { return <Fixora/>; }
