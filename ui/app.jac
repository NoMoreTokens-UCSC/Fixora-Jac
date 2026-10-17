import from "react" { useEffect }
import from "lucide-react" { MessageSquare, LayoutDashboard, Plus, Search, Moon, Sun, Menu, X, ArrowUp, ArrowDown, ChevronRight, ShieldCheck, CircleHelp, Check, LoaderCircle, RefreshCw, AlertCircle, ArrowLeft, Monitor }
import from ..components.ui.button { Button }
import from ..components.ui.input { Input }
import from ..components.ui.textarea { Textarea }
import from ..components.ui.native_select { NativeSelect, NativeSelectOption }
import from ..components.ui.field { Field, FieldLabel }
import from ..components.ui.skeleton { Skeleton }
import from ..components.ui.dialog { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter }
import from ..components.ui.alert_dialog { AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription, AlertDialogFooter, AlertDialogAction, AlertDialogCancel }
import from .gateway { load_cases, refresh_cases, get_case, connect, disconnect, assessment, create_case, send_message, read_image, attach_evidence, remove_evidence, correct_case, advance_case, status_label, error_message, search_cases }
import from .models { CaseRecord, Evidence }
import from .chat { ChatWorkspace }
import from .dashboard { ShopDashboard }
import from .pieces { EmptyState }
import from .login { DemoLogin }
import from .brand { BrandMark }

def:pub Fixora() -> JsxElement {
    has cases: list[CaseRecord] = [];
    has active: CaseRecord = CaseRecord();
    has loaded: bool = False;
    has busy: bool = False;
    has upload_percent: int = -1;
    has view: str = "chat";
    has login_role: str = "";
    has detail_tab: str = "assessment";
    has persona: str = "alex";
    has detail: bool = False;
    has side_open: bool = False;
    has dark: bool = False;
    has notice: bool = False;
    has error: str = "";
    has success: str = "";
    has draft: str = "";
    has modal: str = "";
    has confirm: str = "";
    has query: str = "";
    has search_matches: list[CaseRecord] = [];
    has searching: bool = False;
    has search_token: Ref[int] = Ref(0);
    has model: str = "Fixora Demo FD-100";
    has note: str = "";
    has evidence_id: str = "";
    has pending_id: str = "";
    has pending_view: str = "chat";
    has pending_persona: str = "alex";
    has pending_detail: bool = False;
    has scrolled: bool = False;
    has scrollRef: Ref[HTMLDivElement] = Ref();
    has progressRef: Ref[HTMLDivElement] = Ref();
    has focusReturn: Ref[any] = Ref(None);
    has confirmReturn: Ref[any] = Ref(None);
    has pendingFile: Ref[any] = Ref(None);
    has pending_file_kind: str = "photo";
    has operation: Ref[bool] = Ref(False);

    async can with entry {
        try {
            document.title = "Fixora — laptop care";
            sessionStorage.removeItem("fixora-api-token");
            saved_theme = localStorage.getItem("fixora-theme");
            color_media: any = window.matchMedia("(prefers-color-scheme: dark)");
            selected_dark: bool = saved_theme == "dark" if saved_theme else color_media.matches as bool;
            dark = selected_dark;
            document.documentElement.classList.toggle("dark", selected_dark);
            update_icon(selected_dark);
            notice = localStorage.getItem("fixora-storage-notice") != "dismissed";
            saved_role = sessionStorage.getItem("fixora-demo-role");
            if saved_role in ["customer", "owner"] {
                login_role = saved_role as str;
                view = "shop" if saved_role == "owner" else "chat";
            }
            rows: list[CaseRecord] = await refresh_cases();
            cases = rows;
            if len(rows) > 0 { active = await get_case(rows[0].id); }
            if not sessionStorage.getItem("fixora-session-token") { login_role = ""; }
            loaded = True;
        } except Exception as e { error = error_message(e); login_role = ""; disconnect(); sessionStorage.removeItem("fixora-demo-role"); loaded = True; }
    }
    useEffect(lambda {
        handler = lambda (e: any) {
            if login_role and not modal and (e.ctrlKey or e.metaKey) and e.key.lower() == "k" {
                e.preventDefault(); focusReturn.current = document.activeElement; query = ""; modal = "search";
            }
        };
        window.addEventListener("keydown", handler);
        return lambda { window.removeEventListener("keydown", handler); };
    }, [modal, login_role]);
    useEffect(lambda {
        handler = lambda (e: any) {
            if draft.strip() or note.strip() { e.preventDefault(); e.returnValue = ""; }
        };
        window.addEventListener("beforeunload", handler);
        return lambda { window.removeEventListener("beforeunload", handler); };
    }, [draft, note]);
    useEffect(lambda {
        if scrollRef.current { scrollRef.current.scrollTop = 0; }
        if progressRef.current { progressRef.current.style.width = "0%"; }
        scrolled = False;
    }, [view, active.id, detail]);

    def set_draft(text: str) { draft = text; error = ""; success = ""; }
    async def login(role: str, email: str, password: str) -> None {
        if role not in ["customer", "owner"] { return; }
        await connect(role, email, password);
        try {
            rows: list[CaseRecord] = await refresh_cases();
            cases = rows;
            active = await get_case(rows[0].id) if len(rows) > 0 else CaseRecord();
        } except Exception as failure { disconnect(); raise failure; }
        login_role = role; persona = "alex"; loaded = True;
        view = "shop" if role == "owner" else "chat"; detail = False; error = "";
        sessionStorage.setItem("fixora-demo-role", role);
    }
    def logout() {
        if operation.current { return; }
        if draft.strip() or note.strip() { request_confirmation("logout"); return; }
        finish_logout();
    }
    def finish_logout() {
        sessionStorage.removeItem("fixora-demo-role");
        disconnect(); cases = []; active = CaseRecord();
        login_role = ""; view = "chat"; persona = "alex"; detail = False;
        side_open = False; modal = ""; confirm = ""; draft = ""; note = ""; error = ""; success = "";
    }
    def change_tab(value: str) { detail_tab = value; }
    def open_customer_chats() { detail_tab = "conversation"; navigate(active.id, "shop", True, persona); }
    def request_confirmation(kind: str) { confirmReturn.current = document.activeElement; confirm = kind; }
    def restore_confirmation(e: any) {
        e.preventDefault();
        if confirmReturn.current and confirmReturn.current.isConnected { confirmReturn.current.focus(); }
        elif focusReturn.current and focusReturn.current.isConnected { focusReturn.current.focus(); }
    }
    async def find_cases(text: str) -> None {
        query = text; search_token.current = (search_token.current or 0) + 1;
        token = search_token.current; searching = True;
        try {
            matches: list[CaseRecord] = await search_cases(text, persona, view == "shop");
            if token == search_token.current { search_matches = matches; }
        } except Exception as e { error = error_message(e); }
        finally { if token == search_token.current { searching = False; } }
    }
    def open_modal(kind: str) {
        focusReturn.current = document.activeElement;
        if kind == "new" and draft.strip() { request_confirmation("new"); return; }
        modal = kind; note = active.description if kind == "correct" else ""; error = ""; success = ""; model = active.model;
    }
    def close_modal(opened: bool) {
        if not opened {
            if note.strip() { request_confirmation("discard"); }
            else { modal = ""; error = ""; }
        }
    }
    def restore_focus(e: any) { e.preventDefault(); if focusReturn.current { focusReturn.current.focus(); } }
    def navigate(id: str, target: str, show_detail: bool, next_persona: str) {
        if operation.current { success = "Please wait for the current save to finish."; return; }
        if draft.strip() or note.strip() {
            pending_id = id; pending_view = target; pending_persona = next_persona; pending_detail = show_detail; request_confirmation("navigate");
            return;
        }
        switch_view(id, target, show_detail, next_persona);
    }
    async def switch_view(id: str, target: str, show_detail: bool, next_persona: str) -> None {
        if (login_role == "owner" and target != "shop") or (login_role == "customer" and target != "chat") { return; }
        operation.current = True; busy = True;
        try {
            matches = [c for c in cases if not id or c.id == id];
            if id { active = await get_case(id); }
            elif len(matches) > 0 { active = await get_case(matches[0].id); }
            cases = await load_cases();
            view = target; detail = show_detail; persona = next_persona; side_open = False; modal = ""; error = ""; success = "";
        } except Exception as failure { error = error_message(failure); }
        finally { operation.current = False; busy = False; }
    }
    def select_case(id: str) { detail_tab = "assessment"; navigate(id, view, view == "shop", persona); }
    def toggle_theme() {
        next_dark = not dark;
        dark = next_dark;
        document.documentElement.classList.toggle("dark", next_dark);
        update_icon(next_dark);
        try { localStorage.setItem("fixora-theme", "dark" if next_dark else "light"); }
        except Exception { error = "The theme changed, but this browser could not save your preference."; }
    }
    def update_icon(is_dark: bool) {
        icon: any = document.querySelector("link[rel='icon']");
        if not icon { icon = document.createElement("link"); icon.setAttribute("rel", "icon"); head_node: any = document.head; head_node.appendChild(icon); }
        icon.setAttribute("href", "/assets/brand/logo-dark.png" if is_dark else "/assets/brand/logo-light.png");
    }
    def dismiss_notice() { localStorage.setItem("fixora-storage-notice", "dismissed"); notice = False; }
    def on_scroll(e: Event) {
        if scrollRef.current {
            scroll_node: any = scrollRef.current;
            extent: int = (scroll_node.scrollHeight as int) - (scroll_node.clientHeight as int);
            position: float = scroll_node.scrollTop as float;
            amount: float = (position / extent * 100) if extent > 0 else 0.0;
            if progressRef.current { progressRef.current.style.width = str(amount) + "%"; }
            scrolled = position > 360;
        }
    }
    def scroll_content(bottom: bool) {
        if scrollRef.current {
            motion_media: any = window.matchMedia("(prefers-reduced-motion: reduce)");
            behaviour = "auto" if motion_media.matches else "smooth";
            scrollRef.current.scrollTo({"top": scrollRef.current.scrollHeight if bottom else 0, "behavior": behaviour});
        }
    }
    def open_evidence(id: str) { evidence_id = id; open_modal("evidence"); }
    def request_remove(id: str) { evidence_id = id; request_confirmation("remove"); }

    async def run(command: str) -> None {
        if operation.current { return; }
        operation.current = True; busy = True; error = ""; success = "";
        try {
            result = active;
            if command == "create" {
                result = await create_case(persona, model, note);
                view = "shop" if login_role == "owner" else "chat"; detail = login_role == "owner"; draft = "";
            } elif command == "send" {
                result = await send_message(active.id, active.revision, draft);
                draft = "";
            } elif command == "correct" {
                result = await correct_case(active.id, active.revision, model, note, "shop" if view == "shop" else "customer");
            } elif command == "remove" {
                result = await remove_evidence(active.id, active.revision, evidence_id);
            } elif command == "assess" {
                result = await advance_case(active.id, active.revision);
                active = result;
                while result.status == "processing" and result.stage < 5 {
                    result = await advance_case(result.id, result.revision);
                    active = result;
                }
            } elif command == "refresh" {
                refreshed: list[CaseRecord] = await refresh_cases();
                cases = refreshed;
                matches = [c for c in refreshed if c.id == active.id];
                if len(matches) > 0 { result = await get_case(matches[0].id); }
                elif len(refreshed) > 0 { result = await get_case(refreshed[0].id); }
            }
            active = result;
            cases = await load_cases();
            if command not in ["assess", "send", "refresh", "remove"] { modal = ""; note = ""; }
            confirm = "";
            if result.failure { error = result.failure; success = ""; }
            else { success = "Latest case loaded from the server." if command == "refresh" else "Saved to MongoDB."; }
        } except Exception as e { error = error_message(e); confirm = ""; }
        finally { busy = False; operation.current = False; }
    }
    async def send() -> None { await run("send"); }
    def update_upload(value: int) { upload_percent = value; }
    async def upload(file: any, kind: str) -> None {
        if active.status in ["approved", "rejected"] {
            pendingFile.current = file; pending_file_kind = kind; request_confirmation("upload"); return;
        }
        await save_upload(file, kind);
    }
    async def save_upload(file: any, kind: str) -> None {
        if operation.current { return; }
        operation.current = True; busy = True; upload_percent = 0; error = ""; success = "";
        try {
            evidence = await read_image(file, kind, update_upload);
            result = await attach_evidence(active.id, active.revision, evidence);
            active = result; cases = await load_cases(); success = "Image uploaded to MongoDB. Choose Assess complaint to analyse it.";
        } except Exception as e { error = error_message(e); }
        finally { operation.current = False; busy = False; upload_percent = -1; }
    }
    async def action(command: str) -> None {
        if command == "queue" { navigate("", "shop", False, persona); }
        elif command == "correct" { open_modal("correct"); }
        else { await run(command); }
    }
    async def accept_confirmation() -> None {
        if confirm == "logout" { finish_logout(); }
        elif confirm == "navigate" {
            draft = ""; note = ""; confirm = "";
            switch_view(pending_id, pending_view, pending_detail, pending_persona);
        } elif confirm == "discard" { note = ""; modal = ""; confirm = ""; }
        elif confirm == "new" { draft = ""; note = ""; confirm = ""; modal = "new"; }
        elif confirm == "correct" { await run("correct"); }
        elif confirm == "remove" { await run("remove"); }
        elif confirm == "upload" { await save_upload(pendingFile.current, pending_file_kind); pendingFile.current = None; confirm = ""; }
    }

    visible_cases = cases;
    search_results = visible_cases if not query else search_matches;
    evidence_matches = [e for e in active.evidence if e.id == evidence_id];
    modal_title = {"new": "Start a new conversation", "search": "Search your workspace", "correct": "Confirm case details", "storage": "Data and connection", "evidence": "Evidence source"};
    if not login_role { return <DemoLogin dark={dark} onTheme={toggle_theme} onLogin={login}/>; }
    return <div className={"app-shell " + ("sidebar-open" if side_open else "") + (" shop-mode" if view == "shop" else " chat-mode")}>
        {if side_open { <button className="sidebar-scrim" aria-label="Close navigation" onClick={lambda { side_open = False; }}/> }}
        <aside className="app-sidebar" aria-label="Workspace navigation">
            <div className="sidebar-brand"><a href="#" onClick={lambda (e: MouseEvent) { e.preventDefault(); navigate("", view, False, persona); }}><BrandMark/><span>fixora.</span></a><Button variant="ghost" size="icon" className="mobile-only" aria-label="Close navigation" onClick={lambda { side_open = False; }}><X size={18}/></Button></div>
            <div className="workspace-label">{"SHOP OWNER WORKSPACE" if view == "shop" else "CUSTOMER WORKSPACE"}</div>
            <nav className="workspace-nav">{if view == "chat" { <Button variant="ghost" className="nav-item active" onClick={lambda { navigate("", "chat", False, persona); }}><MessageSquare size={17}/>My conversations</Button> } else { <Button variant="ghost" className={"nav-item " + ("active" if not detail else "")} onClick={lambda { navigate("", "shop", False, persona); }}><LayoutDashboard size={17}/>Shop dashboard<span className="nav-count">{len(cases)}</span></Button><Button variant="ghost" className={"nav-item " + ("active" if detail and detail_tab == "conversation" else "")} onClick={open_customer_chats}><MessageSquare size={17}/>Customer chats</Button> }}</nav>
            <div className="sidebar-divider"/>
            {if view == "chat" {
                <Button variant="outline" className="new-conversation" onClick={lambda { open_modal("new"); }} disabled={busy}><Plus size={16}/>New conversation</Button>
                <div className="history-heading">YOUR CONVERSATIONS<span>{len(visible_cases)}</span></div>
                <div className="conversation-history">{for c in visible_cases { <Button key={c.id} variant="ghost" className={"history-item " + ("selected" if active.id == c.id else "")} onClick={lambda { select_case(c.id); }}><MessageSquare size={14}/><span>{c.title}</span>{if c.status == "needs_information" { <span className="unread-dot"/> }}</Button> }}</div>
            } else {
                <div className="shop-sidebar-note"><span className="section-eyebrow">ONE SHOP. EVERY DETAIL.</span><p>Give every complaint the attention it needs.</p><span className="muted tiny">MongoDB cases and configured AI analysis. Shared shop access; demo roles are not customer authentication.</span></div>
            }}
            <div className="sidebar-bottom"><Button variant="ghost" className="help-button" onClick={lambda { open_modal("storage"); }}><CircleHelp size={16}/>About this demo<ChevronRight size={14}/></Button><div className="persona-control"><span className="persona-avatar">{"S" if view == "shop" else "A"}</span><div><strong>{"Shop owner" if view == "shop" else "Alex Morgan"}</strong><span>{"owner@fixora.demo" if view == "shop" else "customer@fixora.demo"}</span></div></div><Button variant="outline" className="sign-out-button" disabled={busy} onClick={logout}>Sign out</Button><span className="local-storage-caption"><span className="saved-dot"/>Shared shop · Saved in MongoDB</span></div>
        </aside>
        <div className="workspace">
            <header className="app-header"><div className="header-left"><Button variant="ghost" size="icon" className="mobile-only" aria-label="Open navigation" onClick={lambda { side_open = True; }}><Menu size={19}/></Button><nav className="breadcrumbs" aria-label="Breadcrumb"><span>{"Shop" if view == "shop" else "Support"}</span><ChevronRight size={13}/><button onClick={lambda { if view == "shop" { navigate("", "shop", False, persona); } }}>{"Complaints" if view == "shop" else "Customer chat"}</button>{if detail and view == "shop" { <ChevronRight size={13}/><strong>{active.reference}</strong> }}</nav></div><div className="header-actions"><span className="demo-badge"><span/>Connected backend</span><Button variant="ghost" className="search-trigger" aria-label="Search workspace" onClick={lambda { query = ""; open_modal("search"); }}><Search size={16}/><span>Search</span><kbd>⌘ K</kbd></Button><Button variant="ghost" size="icon" aria-label={"Switch to light mode" if dark else "Switch to dark mode"} title={"Switch to light mode" if dark else "Switch to dark mode"} onClick={toggle_theme}>{if dark { <Sun size={18}/> } else { <Moon size={18}/> }}</Button></div><div className="reading-progress" aria-hidden="true"><div ref={progressRef}/></div></header>
            {if notice { <div className="storage-banner"><span>Cases and uploaded evidence are saved on the server. This shared shop demo has no customer ownership restrictions.</span><div><Button variant="link" size="sm" onClick={lambda { open_modal("storage"); }}>Details</Button><Button variant="outline" size="sm" onClick={dismiss_notice}>Got it</Button></div></div> }}
            {if error and not modal { <div id="workspace-error" className="feedback error-feedback" role="alert"><AlertCircle size={16}/><span>{error}</span><Button variant="ghost" size="sm" onClick={lambda { action("refresh"); }}>Reload latest</Button><Button variant="ghost" size="icon-sm" aria-label="Dismiss error" onClick={lambda { error = ""; }}><X size={14}/></Button></div> }}
            {if success { <div className="feedback success-feedback" role="status"><Check size={15}/><span>{success}</span><Button variant="ghost" size="icon-sm" aria-label="Dismiss message" onClick={lambda { success = ""; }}><X size={13}/></Button></div> }}
            <main ref={scrollRef} className="main-scroll" onScroll={on_scroll} id="main-content">
                {if not loaded { <div className="loading-screen" role="status" aria-label="Loading saved cases"><Skeleton className="h-10 w-56"/><Skeleton className="h-24 w-full"/><Skeleton className="h-24 w-3/4"/></div> } elif not active.id { <div><EmptyState title="No repair requests yet" text="Create a conversation to upload an invoice and photos for assessment."/><Button onClick={lambda { open_modal("new"); }}>New conversation</Button></div> } elif view == "chat" { <ChatWorkspace c={active} draft={draft} busy={busy} upload_percent={upload_percent} error={error} onDraft={set_draft} onSend={send} onAction={action} onFile={upload} onEvidence={open_evidence} onRemove={request_remove}/> } else { <ShopDashboard cases={cases} c={active} detail={detail} busy={busy} tab={detail_tab} onTab={change_tab} draft={draft} error={error} onDraft={set_draft} onSelect={select_case} onAction={action} onEvidence={open_evidence}/> }}
            </main>
            <div className={"floating-actions " + ("detail-floating" if detail and view == "shop" else "")} aria-label="Quick actions">{if view == "chat" {
                <Button variant="outline" size="icon" aria-label="Start new complaint" title="New complaint" onClick={lambda { open_modal("new"); }}><Plus size={17}/></Button>
                if scrolled { <Button variant="outline" size="icon" aria-label="Jump to latest message" onClick={lambda { scroll_content(True); }}><ArrowDown size={17}/></Button> }
            } elif detail { <Button variant="outline" size="icon" aria-label="Return to complaint inbox" onClick={lambda { action("queue"); }}><ArrowLeft size={17}/></Button> }
            if scrolled { <Button variant="outline" size="icon" aria-label="Back to top" onClick={lambda { scroll_content(False); }}><ArrowUp size={17}/></Button> }
            }</div>
        </div>
        <Dialog open={bool(modal)} onOpenChange={close_modal}><DialogContent className={"app-dialog " + ("evidence-dialog" if modal == "evidence" else "")} onCloseAutoFocus={restore_focus}><DialogHeader><DialogTitle>{(modal_title[modal] as str) if modal_title[modal] else "Fixora"}</DialogTitle><DialogDescription>{"Search the shared shop cases." if modal == "search" else "Cases, evidence and assessment results are saved on the server."}</DialogDescription></DialogHeader>
            {if modal == "search" { <div className="search-dialog-body"><Input aria-label="Search cases and messages" autoFocus={True} value={query} onChange={lambda (e: ChangeEvent) { find_cases(e.target.value); }} placeholder="Case reference, device, complaint or message…"/><div className="search-results">{for c in search_results { <Button key={c.id} variant="ghost" className="search-result" onClick={lambda { select_case(c.id); }}><MessageSquare size={17}/><span><strong>{c.title}</strong><small>{c.reference + " · " + c.model + " · " + status_label(c.status)}</small></span><ChevronRight size={15}/></Button> }}{if len(search_results) == 0 { <EmptyState title="No matches" text="Try a different word or case reference."/> }}</div></div> }}
            {if modal == "new" { <div className="modal-fields"><Field><FieldLabel htmlFor="new-model">Your laptop model</FieldLabel><NativeSelect id="new-model" value={model} onChange={lambda (e: ChangeEvent) { model = e.target.value; }}><NativeSelectOption value="Fixora Demo FD-100">Fixora Demo FD-100</NativeSelectOption><NativeSelectOption value="Fixora Demo FD-200">Fixora Demo FD-200</NativeSelectOption><NativeSelectOption value="Fixora Demo FD-300">Fixora Demo FD-300</NativeSelectOption></NativeSelect></Field><Field><FieldLabel htmlFor="new-description">Describe the problem</FieldLabel><Textarea id="new-description" value={note} maxLength={4000} onChange={lambda (e: ChangeEvent) { note = e.target.value; error = ""; }} placeholder="For example: The display is visibly cracked. Please estimate a display replacement."/></Field><div className="notice-box"><ShieldCheck size={17}/><span>Upload your invoice and product photos after creating the case. The server uses its configured model; no sample scenario is selected here.</span></div><DialogFooter><Button disabled={busy or not note.strip()} onClick={lambda { run("create"); }}>Start conversation<Plus size={15}/></Button></DialogFooter></div> }}
            {if modal == "correct" { <div className="modal-fields"><Field><FieldLabel htmlFor="correct-model">Confirmed laptop model</FieldLabel><NativeSelect id="correct-model" value={model} onChange={lambda (e: ChangeEvent) { model = e.target.value; }}><NativeSelectOption value="Fixora Demo FD-100">Fixora Demo FD-100</NativeSelectOption><NativeSelectOption value="Fixora Demo FD-200">Fixora Demo FD-200</NativeSelectOption><NativeSelectOption value="Fixora Demo FD-300">Fixora Demo FD-300</NativeSelectOption></NativeSelect></Field><Field><FieldLabel htmlFor="correction-note">Corrected problem description *</FieldLabel><Textarea id="correction-note" aria-invalid={bool(error) and not note.strip()} aria-describedby={"workspace-error" if error else None} value={note} onChange={lambda (e: ChangeEvent) { note = e.target.value; error = ""; }} placeholder="Enter the complete corrected problem description."/></Field><p className="muted small">A new revision requires reassessment. The server archives the previous assessment.</p><DialogFooter><Button disabled={busy} onClick={lambda { if note.strip() { request_confirmation("correct"); } else { error = "Explain the correction before saving."; } }}>Save correction</Button></DialogFooter></div> }}
            {if modal == "storage" { <div className="modal-fields"><p>Cases and assessment results are stored in MongoDB. Uploaded images are stored in GridFS. A temporary sign-in session and selected demo role are kept in this browser tab; theme preferences are kept on this device.</p><p>Both demo roles share the shop queue. Production customer ownership, chat replies, inspection records and approval decisions are not implemented in the backend.</p><p>Document and vision extraction use the configured model. Policy, stock compatibility and prices use shop catalogue rules. Explicit server fixture mode is labelled in each result.</p></div> }}
            {if modal == "evidence" { <div className="evidence-viewer">{if evidence_id == "policy" { <div className="policy-source"><h3>Applied policy clauses</h3><p>{assessment(active).policy}</p><pre style={{"whiteSpace": "pre-wrap"}}>{JSON.stringify(assessment(active).clauses, None, 2)}</pre><p>Date eligibility alone does not establish coverage. Policy clauses are loaded from the saved assessment.</p></div> } elif len(evidence_matches) > 0 { <figure><img src={evidence_matches[0].preview} alt={evidence_matches[0].name}/><figcaption>{evidence_matches[0].name + " · " + evidence_matches[0].mime}</figcaption></figure> } else { <EmptyState title="Evidence unavailable" text="Reload the case to retrieve its current evidence."/> }}</div> }}
            {if error and modal { <div id="workspace-error" className="inline-error" role="alert"><AlertCircle size={15}/><span>{error}</span><Button variant="outline" size="sm" onClick={lambda { run("refresh"); }}>Load latest case</Button></div> }}
        </DialogContent></Dialog>
        <AlertDialog open={bool(confirm)} onOpenChange={lambda (opened: bool) { if not opened { confirm = ""; } }}><AlertDialogContent className="confirmation-dialog" onCloseAutoFocus={restore_confirmation}><AlertDialogHeader><AlertDialogTitle>{"Discard unsaved changes?" if confirm in ["navigate", "discard", "new", "logout"] else ("Remove this attachment?" if confirm == "remove" else ("Create a revised assessment?"))}</AlertDialogTitle><AlertDialogDescription>{"Your unsent message or notes will be discarded. Saved cases remain available." if confirm in ["navigate", "discard", "new", "logout"] else ("This saves a new case revision. The server archives the previous assessment; current inputs need reassessment." if confirm in ["correct", "remove", "upload"] else "Your changes are saved on the server. No payment or stock reservation occurs.")}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={busy}>Keep editing</AlertDialogCancel><AlertDialogAction disabled={busy} onClick={lambda (e: MouseEvent) { e.preventDefault(); accept_confirmation(); }}>{if busy { <LoaderCircle size={14} className="spin"/> }}Confirm</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    </div>;
}
