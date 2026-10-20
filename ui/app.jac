import from "react" { useEffect }
import from "lucide-react" { LayoutDashboard, MessageSquare, Search, Moon, Sun, Menu, X, ChevronRight, CircleHelp, Check, LoaderCircle, AlertCircle, RefreshCw }
import from ..components.ui.button { Button }
import from ..components.ui.input { Input }
import from ..components.ui.textarea { Textarea }
import from ..components.ui.native_select { NativeSelect, NativeSelectOption }
import from ..components.ui.field { Field, FieldLabel }
import from ..components.ui.dialog { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter }
import from ..components.ui.alert_dialog { AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription, AlertDialogFooter, AlertDialogAction, AlertDialogCancel }
import from .gateway { uid, load_cases, load_models, get_case, owner_session, owner_logout, owner_request, send_shop_message, save_internal_note, correct_case, inspect_case, review_case, advance_case, retry_delivery, error_message }
import from .models { CaseRecord }
import from .dashboard { ShopDashboard }
import from .pieces { EmptyState }
import from .login { DemoLogin }
import from .brand { BrandMark }

def:pub Fixora() -> JsxElement {
    has cases: list[CaseRecord] = [];
    has active: CaseRecord = CaseRecord();
    has model_options: list[str] = [];
    has loaded: bool = False;
    has signed_in: bool = False;
    has busy: bool = False;
    has detail: bool = False;
    has detail_tab: str = "assessment";
    has side_open: bool = False;
    has dark: bool = False;
    has error: str = "";
    has success: str = "";
    has draft: str = "";
    has modal: str = "";
    has confirm: bool = False;
    has model: str = "";
    has note: str = "";
    has diagnosis: str = "unknown";
    has review_action: str = "approved";
    has evidence_id: str = "";
    has policy_text: str = "";
    has query: str = "";
    has chat_rows: list[any] = [];
    has chat_id: str = "";
    has catalogue_rows: list[any] = [];
    has operation: Ref[bool] = Ref(False);

    async can with entry {
        document.title = "Fixora — shop workspace";
        saved_theme = localStorage.getItem("fixora-theme");
        selected_dark = saved_theme == "dark";
        dark = selected_dark;
        document.documentElement.classList.toggle("dark", selected_dark);
        try {
            if await owner_session() {
                signed_in = True;
                rows = await load_cases(); cases = rows; model_options = await load_models();
                if len(rows) > 0 { active = rows[0]; }
            }
        } except Exception as e { error = error_message(e); }
        finally { loaded = True; }
    }

    def polling() -> any {
        if not signed_in or modal or draft.strip() or note.strip() { return; }
        guard: any = {"cancelled": False, "running": False};
        async def tick() -> None {
            if operation.current or guard.running { return; }
            guard.running = True;
            try {
                rows = await load_cases();
                if not guard.cancelled and not operation.current {
                    cases = rows;
                    matches = [c for c in rows if c.id == active.id];
                    if len(matches) > 0 { active = matches[0]; }
                    elif len(rows) > 0 { active = rows[0]; }
                }
            } except Exception as e { if not guard.cancelled { error = error_message(e); } }
            finally { guard.running = False; }
        }
        timer = window.setInterval(tick, 4000);
        return lambda { guard.cancelled = True; window.clearInterval(timer); };
    }
    useEffect(polling, [signed_in, modal, draft, note, active.id]);
    useEffect(lambda {
        expired_handler = lambda { signed_in = False; cases = []; chat_rows = []; chat_id = ""; catalogue_rows = []; active = CaseRecord(); draft = ""; note = ""; modal = ""; };
        window.addEventListener("fixora-session-expired", expired_handler);
        return lambda { window.removeEventListener("fixora-session-expired", expired_handler); };
    }, []);
    useEffect(lambda {
        unload_handler = lambda (e: any) { if draft.strip() or note.strip() { e.preventDefault(); e.returnValue = ""; } };
        window.addEventListener("beforeunload", unload_handler);
        return lambda { window.removeEventListener("beforeunload", unload_handler); };
    }, [draft, note]);

    async def login(role: str) -> None {
        signed_in = True; error = "";
        try { rows = await load_cases(); cases = rows; model_options = await load_models(); if len(rows) > 0 { active = rows[0]; } }
        except Exception as e { error = error_message(e); }
    }
    async def logout() -> None {
        if busy { return; }
        if draft.strip() or note.strip() { error = "Send or clear your unsaved text before signing out."; return; }
        try { await owner_logout(); signed_in = False; cases = []; chat_rows = []; chat_id = ""; catalogue_rows = []; active = CaseRecord(); detail = False; error = ""; }
        except Exception as e { error = error_message(e); }
    }
    def toggle_theme() {
        next_dark = not dark; dark = next_dark; document.documentElement.classList.toggle("dark", next_dark);
        localStorage.setItem("fixora-theme", "dark" if next_dark else "light");
    }
    def set_draft(value: str) { draft = value; error = ""; success = ""; }
    def change_tab(value: str) { detail_tab = value; }
    async def select_case(id: str) -> None {
        if busy { return; }
        if draft.strip() or note.strip() { error = "Send or clear your unsaved text before switching cases."; return; }
        try { active = await get_case(id); detail = True; detail_tab = "assessment"; side_open = False; error = ""; }
        except Exception as e { error = error_message(e); }
    }
    def open_modal(kind: str) {
        modal = kind; error = ""; note = active.description if kind == "correct" else "";
        model = active.model if active.model in model_options else (model_options[0] if len(model_options) > 0 else "");
        diagnosis = "unknown";
    }
    async def open_evidence(id: str) -> None {
        evidence_id = id; modal = "evidence"; error = "";
        if id == "policy" {
            try { data = await owner_request("/owner/policy"); policy_text = JSON.stringify(data.policy, None, 2); }
            except Exception as e { error = error_message(e); }
        }
    }
    async def open_browser(kind: str) -> None {
        if busy { return; }
        if draft.strip() or note.strip() { error = "Send or clear your unsaved text first."; return; }
        busy = True; error = "";
        try {
            if kind == "conversations" {
                data = await owner_request("/owner/conversations"); chat_rows = data.conversations;
                if not chat_id and len(chat_rows) > 0 { chat_id = chat_rows[0].id as str; }
            } else { data = await owner_request("/owner/catalogue"); catalogue_rows = data.items; }
            modal = kind;
        } except Exception as e { error = error_message(e); }
        finally { busy = False; }
    }
    async def send_chat(is_private: bool) -> None {
        if busy or not chat_id or not note.strip() { return; }
        busy = True; error = "";
        try {
            await owner_request("/owner/conversations/" + encodeURIComponent(chat_id) + "/messages", "POST", {"request_id": uid(), "text": note, "internal": is_private});
            note = "";
            data = await owner_request("/owner/conversations"); chat_rows = data.conversations;
            success = "Private note saved." if is_private else "Reply queued for WhatsApp.";
        } except Exception as e { error = error_message(e); }
        finally { busy = False; }
    }
    async def run(command: str) -> None {
        if operation.current { return; }
        operation.current = True; busy = True; error = ""; success = "";
        try {
            result = active;
            if command == "shop_reply" { result = await send_shop_message(active.id, active.revision, draft); draft = ""; }
            elif command == "note" { result = await save_internal_note(active.id, active.revision, note); }
            elif command == "correct" { result = await correct_case(active.id, active.revision, model, note); }
            elif command == "inspection" { result = await inspect_case(active.id, active.revision, diagnosis, note); }
            elif command == "review" { result = await review_case(active.id, active.revision, review_action, note); }
            elif command == "assess" { result = await advance_case(active.id, active.revision); }
            elif command[:15] == "retry_delivery:" { result = await retry_delivery(active.id, active.revision, command[15:]); }
            rows = await load_cases(); cases = rows;
            matches = [c for c in rows if c.id == result.id];
            if len(matches) > 0 { active = matches[0]; }
            elif len(rows) > 0 { active = rows[0]; }
            modal = ""; note = ""; confirm = False;
            success = "Assessment queued. The worker will process it independently." if command == "assess" else ("Reply queued for WhatsApp. Delivery status appears in the conversation." if command == "shop_reply" else "Latest saved case loaded." if command in ["refresh", "check_parts", "retry_parts"] else "Saved to the case record.");
        } except Exception as e { error = error_message(e); confirm = False; }
        finally { busy = False; operation.current = False; }
    }
    async def action(command: str) -> None {
        if command == "queue" { if draft.strip() { error = "Send or clear your unsaved reply first."; } else { detail = False; } }
        elif command in ["correct", "inspection", "note"] { open_modal(command); }
        elif command in ["approve", "reject", "request_info", "request_inspection"] {
            review_action = "approved" if command == "approve" else ("rejected" if command == "reject" else ("needs_information" if command == "request_info" else "needs_inspection"));
            open_modal("review");
        } else { await run(command); }
    }
    def close_modal(opened: bool) { if not opened { modal = ""; note = ""; confirm = False; } }
    evidence_matches = [e for e in active.evidence if e.id == evidence_id];
    selected_chats = [c for c in chat_rows if c.id == chat_id];
    search_results = [c for c in cases if not query or query.lower() in (c.reference + " " + c.customer + " " + c.title).lower()];
    titles: dict = {"conversations": "WhatsApp conversations", "catalogue": "Products, parts and accessories", "correct": "Correct case details", "inspection": "Record an inspection", "review": "Review repair proposal", "note": "Internal shop note", "evidence": "Evidence source", "search": "Search saved cases", "about": "About this workspace"};
    if not loaded { return <main className="loading-screen" role="status"><LoaderCircle className="spin"/>Loading owner session…</main>; }
    if not signed_in { return <DemoLogin dark={dark} onTheme={toggle_theme} onLogin={login}/>; }
    return <div className={"app-shell shop-mode " + ("sidebar-open" if side_open else "")}>
        {if side_open { <button className="sidebar-scrim" aria-label="Close navigation" onClick={lambda { side_open = False; }}/> }}
        <aside className="app-sidebar" aria-label="Workspace navigation"><div className="sidebar-brand"><a href="#" onClick={lambda (e: MouseEvent) { e.preventDefault(); action("queue"); }}><BrandMark/><span>fixora.</span></a><Button variant="ghost" size="icon" className="mobile-only" aria-label="Close navigation" onClick={lambda { side_open = False; }}><X size={18}/></Button></div><div className="workspace-label">SHOP OWNER WORKSPACE</div><nav className="workspace-nav"><Button variant="ghost" className="nav-item active" onClick={lambda { action("queue"); }}><LayoutDashboard size={17}/>Shop dashboard<span className="nav-count">{len(cases)}</span></Button><Button variant="ghost" className="nav-item" disabled={busy} onClick={lambda { open_browser("conversations"); }}><MessageSquare size={17}/>Customer conversations</Button><Button variant="ghost" className="nav-item" disabled={busy} onClick={lambda { open_browser("catalogue"); }}>Products and stock</Button></nav><div className="sidebar-divider"/><div className="shop-sidebar-note"><span className="section-eyebrow">WHATSAPP CONNECTED</span><p>Every case, with the context you need.</p><span className="muted tiny">Customers share evidence and receive updates in WhatsApp. The shop reviews proposals here.</span></div><div className="sidebar-bottom"><Button variant="ghost" onClick={lambda { open_modal("about"); }}><CircleHelp size={16}/>About this workspace</Button><Button variant="outline" disabled={busy} onClick={logout}>Sign out</Button><span className="local-storage-caption">Cases saved in MongoDB</span></div></aside>
        <div className="workspace"><header className="app-header"><div className="header-left"><Button variant="ghost" size="icon" className="mobile-only" aria-label="Open navigation" onClick={lambda { side_open = True; }}><Menu size={19}/></Button><nav className="breadcrumbs"><span>Shop</span><ChevronRight size={13}/><button onClick={lambda { action("queue"); }}>Complaints</button></nav></div><div className="header-actions"><Button variant="ghost" aria-label="Search cases" onClick={lambda { modal = "search"; query = ""; }}><Search size={16}/>Search</Button><Button variant="ghost" size="icon" aria-label={"Switch to light mode" if dark else "Switch to dark mode"} onClick={toggle_theme}>{if dark { <Sun size={18}/> } else { <Moon size={18}/> }}</Button></div></header>
        {if error { <div className="feedback error-feedback" role="alert"><AlertCircle size={16}/><span>{error}</span><Button variant="ghost" size="sm" onClick={lambda { run("refresh"); }}>Load latest</Button></div> }}
        {if success { <div className="feedback success-feedback" role="status"><Check size={15}/><span>{success}</span><Button variant="ghost" size="icon" aria-label="Dismiss" onClick={lambda { success = ""; }}><X size={14}/></Button></div> }}
        <main className="main-scroll" id="main-content"><ShopDashboard cases={cases} c={active} detail={detail and bool(active.id)} busy={busy} tab={detail_tab} onTab={change_tab} draft={draft} error={error} onDraft={set_draft} onSelect={select_case} onAction={action} onEvidence={open_evidence}/></main></div>
        <Dialog open={bool(modal)} onOpenChange={close_modal}><DialogContent className="workspace-dialog"><DialogHeader><DialogTitle>{titles[modal] or "Case details"}</DialogTitle><DialogDescription>{"Changes are saved to the shared case. Evidence corrections require a new assessment." if modal in ["correct", "inspection"] else "Customer-visible messages are queued for WhatsApp delivery. Internal notes stay private."}</DialogDescription></DialogHeader>
            {if modal == "conversations" { <div className="dialog-form">
                <Field><FieldLabel htmlFor="chat-customer">Customer</FieldLabel><NativeSelect id="chat-customer" value={chat_id} disabled={busy or bool(note.strip())} onChange={lambda (e: ChangeEvent) { chat_id = e.target.value; }}>{for chat in chat_rows { <NativeSelectOption key={chat.id} value={chat.id}>{str(chat.customer) + " · " + str(chat.sender_id)}</NativeSelectOption> }}</NativeSelect></Field>
                <div style={{"maxHeight": "40vh", "overflowY": "auto"}}>{for chat in selected_chats { <div key={chat.id}>{for message in chat.messages { <article key={message.id} className="storage-details"><strong>{str(message.role) + (" · Private note" if message.internal else "") + (" · Voice transcript" if message.input_kind == "audio" else "")}</strong><p style={{"whiteSpace": "pre-wrap"}}>{message.text}</p><small>{str(message.at) + " " + str(message.delivery)}</small></article> }}</div> }}</div>
                {if len(chat_rows) == 0 { <p>No WhatsApp conversations yet.</p> }}{if error { <p role="alert">{error}</p> }}
                <Field><FieldLabel htmlFor="chat-message">Reply or private note</FieldLabel><Textarea id="chat-message" value={note} maxLength={4000} onChange={lambda (e: ChangeEvent) { note = e.target.value; }}/></Field>
                <DialogFooter><Button variant="outline" disabled={busy or bool(note.strip())} onClick={lambda { open_browser("conversations"); }}>Refresh</Button><Button variant="outline" disabled={busy or not chat_id or not note.strip()} onClick={lambda { send_chat(True); }}>Save private note</Button><Button disabled={busy or not chat_id or not note.strip()} onClick={lambda { send_chat(False); }}>Send reply</Button></DialogFooter>
            </div> }}
            {if modal == "catalogue" { <div style={{"maxHeight": "60vh", "overflowY": "auto"}}><p>Saved stock and prices for customer enquiries. Fictional records are marked DEMO.</p>{for item in catalogue_rows { <article key={item.id} className="storage-details"><strong>{str(item.name) + " · " + str(item.code)}</strong><p>{str(item.category) + (" · DEMO" if item.synthetic else "")}</p><p>{"Stock: " + (str(item.quantity_available) if item.quantity_available is not None else "Not confirmed") + " · Price: " + (str(item.currency) + " " + str((item.unit_price_minor as int) / 100) if item.unit_price_minor is not None and item.currency else "Not confirmed")}</p><small>{", ".join(item.compatible_models as list[str])}</small></article> }}</div> }}
            {if modal in ["correct", "inspection", "review", "note"] { <div className="dialog-form">
                {if modal == "correct" { <Field><FieldLabel htmlFor="case-model">Catalogue model</FieldLabel><NativeSelect id="case-model" value={model} onChange={lambda (e: ChangeEvent) { model = e.target.value; }}>{for value in model_options { <NativeSelectOption key={value} value={value}>{value}</NativeSelectOption> }}</NativeSelect></Field> }}
                {if modal == "inspection" { <Field><FieldLabel htmlFor="case-diagnosis">Confirmed observation</FieldLabel><NativeSelect id="case-diagnosis" value={diagnosis} onChange={lambda (e: ChangeEvent) { diagnosis = e.target.value; }}>{for value in ["unknown", "screen_crack", "hinge_damage", "keyboard_damage"] { <NativeSelectOption key={value} value={value}>{value.replace("_", " ")}</NativeSelectOption> }}</NativeSelect></Field> }}
                {if modal == "review" { <p>{"Decision: " + review_action.replace("_", " ")}</p> }}
                <Field><FieldLabel htmlFor="case-notes">{"Corrected issue description" if modal == "correct" else ("Internal inspection findings" if modal == "inspection" else ("Private note" if modal == "note" else "Customer-facing reason"))}</FieldLabel><Textarea id="case-notes" value={note} maxLength={3000} onChange={lambda (e: ChangeEvent) { note = e.target.value; }}/></Field>
                <DialogFooter><Button variant="outline" disabled={busy} onClick={lambda { close_modal(False); }}>Cancel</Button><Button disabled={busy or not note.strip()} onClick={lambda { confirm = True; }}>Review and save</Button></DialogFooter></div> }}
            {if modal == "evidence" { <div className="evidence-viewer">{if evidence_id == "policy" { <pre style={{"whiteSpace": "pre-wrap"}}>{policy_text}</pre> } elif len(evidence_matches) > 0 { <figure><img src={evidence_matches[0].preview} alt={evidence_matches[0].name}/><figcaption>{evidence_matches[0].name}</figcaption></figure> } else { <EmptyState title="Evidence unavailable" text="Refresh the current case."/> }}</div> }}
            {if modal == "search" { <div><Input aria-label="Search saved cases" value={query} onChange={lambda (e: ChangeEvent) { query = e.target.value; }}/>{for c in search_results { <Button key={c.id} variant="ghost" onClick={lambda { modal = ""; select_case(c.id); }}>{c.title + " · " + c.customer}</Button> }}</div> }}
            {if modal == "about" { <div className="storage-details"><p>Cases, messages, evidence and decisions are saved in MongoDB and GridFS. Your theme preference is saved in this browser.</p><p>WhatsApp receives customer-visible replies. Internal notes remain in the owner workspace. Assessment and message delivery run in a separate worker.</p><p>The catalogue and warranty policy are fictional demonstration data. Repair proposals require owner review; no payment or stock reservation occurs.</p></div> }}
        </DialogContent></Dialog>
        <AlertDialog open={confirm} onOpenChange={lambda (opened: bool) { confirm = opened; }}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Confirm this case update</AlertDialogTitle><AlertDialogDescription>{"The reason will be saved in decision history and queued for the customer in WhatsApp." if modal == "review" else "This update will be saved to the shared case. Internal notes are never sent to WhatsApp."}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={busy}>Keep editing</AlertDialogCancel><AlertDialogAction disabled={busy} onClick={lambda (e: MouseEvent) { e.preventDefault(); run(modal); }}>{if busy { <LoaderCircle size={14} className="spin"/> }}Confirm</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    </div>;
}
