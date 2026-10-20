# Narrow application-local workarounds for the verified Jac full servers.
# No installed package is modified. Revalidate/remove when upgrading Jac.
import importlib;
import inspect;
import from importlib.metadata { version }
import from threading { RLock }
import from jaclang { JacRuntime as Jac }
import from jaclang.jac0core.constructs { Root }
import from jaclang.jac0core.constant { Constants as Con }

glob _original_reset: any = None;
glob _original_print: any = None;
glob _original_introspect: any = None;
glob _guest_lock: RLock = RLock();
glob _installed: bool = False;

def _typed_callable_defaults(self: any, func: any) -> dict[str, any] {
    result = _original_introspect(self, func);
    # The bundled introspector stringifies defaults, so an omitted int default
    # becomes "20" in Pydantic and reaches the function as str. Preserve values.
    signature = inspect.signature(func);
    for (name, parameter) in signature.parameters.items() {
        if name in result["parameters"] and parameter.default is not inspect.Parameter.empty {
            result["parameters"][name]["default"] = parameter.default;
        }
    }
    return result as dict[str, any];
}

def _safe_console_print(self: any, *args: any, **kwargs: any) {
    # The full server unconditionally prints kwargs, including uploads and tokens.
    if args and isinstance(args[0], str) and args[0].startswith("Executing function '") {
        _original_print(self, args[0].split(" with params:", 1)[0] + " (parameters omitted)", **kwargs);
        return;
    }
    _original_print(self, *args, **kwargs);
}

def _reset_guest_root(self: any, username: str) -> str | None {
    if username != Con.GUEST.value { return _original_reset(self, username) as str | None; }
    # Scale's inherited reset_root uses the core users table and uninitialized
    # _lock; recover ONLY the shared guest using Scale's own identity store.
    _guest_lock.acquire();
    try {
        storage = self._identity_storage;
        user = storage.get_user_by_id(username) or storage.find_user_by_identity(username);
        if user is None { return None; }
        guest = Root();
        anchor = guest.__jac__;
        Jac.save(anchor);
        Jac.commit(anchor);
        root_id = anchor.id.hex;
        if not storage.update_user_fields(user["user_id"], {"root_id": root_id}) { return None; }
        return root_id as str;
    } finally { _guest_lock.release(); }
}

def _install_runtime_compat() {
    if _installed or version("jaclang") not in ["0.34.6", "0.34.13"] { return; }
    try { manager = importlib.import_module("jaclang.scale.identity.user_manager").JacScaleUserManager; }
    except ImportError { return; }
    console_class = importlib.import_module("jaclang.cli.console").JacConsole;
    introspector = importlib.import_module("jaclang.runtimelib.server").ModuleIntrospector;
    _original_reset = manager.reset_root;
    _original_print = console_class.print;
    _original_introspect = introspector.introspect_callable;
    setattr(manager, "reset_root", _reset_guest_root);
    setattr(console_class, "print", _safe_console_print);
    setattr(introspector, "introspect_callable", _typed_callable_defaults);
    _installed = True;
}
