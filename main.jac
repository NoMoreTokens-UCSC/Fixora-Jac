import from .ui.app { Fixora }
import ".styles.global.css";
import ".ui.styles.css";
import ".ui.login.css";

def:pub app() -> JsxElement { return <Fixora/>; }
