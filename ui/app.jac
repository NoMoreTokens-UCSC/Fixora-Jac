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
import from .gateway { load_cases, refresh_cases, create_case, send_message, send_shop_message, read_image, attach_evidence, remove_evidence, correct_case, inspect_case, review_case, advance_case, check_parts, status_label, error_message, search_cases }
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
    has model: str = "Studio 14";
    has scenario: str = "complete";
    has note: str = "";
    has diagnosis: str = "";
    has review_action: str = "approved";
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
            rows: list[CaseRecord] = await load_cases();
            cases = rows;
            if len(rows) > 0 { active = rows[0]; }
            loaded = True;
        } except Exception as e { error = "Browser storage could not be opened. Allow site storage, then reload. " + str(e); loaded = True; }
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
    def login(role: str) {
        if role not in ["customer", "owner"] { return; }
        login_role = role; persona = "alex";
        sessionStorage.setItem("fixora-demo-role", role);
        switch_view("", "shop" if role == "owner" else "chat", False, "alex");
    }
    def logout() {
        if operation.current { return; }
        if draft.strip() or note.strip() { request_confirmation("logout"); return; }
        finish_logout();
    }
    def finish_logout() {
        sessionStorage.removeItem("fixora-demo-role");
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
        modal = kind; note = ""; error = ""; success = ""; model = active.model; diagnosis = "";
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
    def switch_view(id: str, target: str, show_detail: bool, next_persona: str) {
        if (login_role == "owner" and target != "shop") or (login_role == "customer" and target != "chat") { return; }
        matches = [c for c in cases if (not id or c.id == id) and (target == "shop" or c.customer_id == next_persona)];
        if len(matches) > 0 { active = matches[0]; }
        view = target; detail = show_detail; persona = next_persona; side_open = False; modal = ""; error = ""; success = "";
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
                result = await create_case(persona, model, scenario);
                view = "chat"; detail = False; draft = "";
            } elif command == "send" {
                result = await send_message(active.id, active.revision, draft);
                draft = "";
            } elif command == "shop_reply" {
                result = await send_shop_message(active.id, active.revision, draft);
                draft = "";
            } elif command == "correct" {
                result = await correct_case(active.id, active.revision, model, note, "shop" if view == "shop" else "customer");
            } elif command == "inspection" {
                result = await inspect_case(active.id, active.revision, diagnosis, note);
            } elif command == "review" {
                result = await review_case(active.id, active.revision, review_action, note);
            } elif command == "remove" {
                result = await remove_evidence(active.id, active.revision, evidence_id);
            } elif command in ["check_parts", "retry_parts"] {
                result = await check_parts(active.id, active.revision, command == "retry_parts");
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
                if len(matches) > 0 { result = matches[0]; }
            }
            active = result;
            cases = await load_cases();
            if command not in ["assess", "send", "shop_reply", "refresh", "remove", "check_parts", "retry_parts"] { modal = ""; note = ""; }
            confirm = "";
            success = "Reply sent to the customer's chat on this browser." if command == "shop_reply" else ("Latest saved case loaded." if command == "refresh" else "Saved on this browser.");
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
            active = result; cases = await load_cases(); success = "Image saved locally. It has not been analysed by AI.";
        } except Exception as e { error = error_message(e); }
        finally { operation.current = False; busy = False; upload_percent = -1; }
    }
    async def action(command: str) -> None {
        if command == "ask_part" {
            if draft.strip() { success = "Your unsent message is still in the composer. Send or clear it before asking about the part."; }
            else { draft = "I'm interested in " + active.availability.part_name + " (" + active.availability.sku + "). Can we discuss collection or installation?"; }
            scroll_content(True);
        }
        elif command == "queue" { navigate("", "shop", False, persona); }
        elif command == "correct" { open_modal("correct"); }
        elif command == "inspection" { open_modal("inspection"); }
        elif command in ["approve", "reject", "request_info", "request_inspection"] {
            review_action = "approved" if command == "approve" else ("rejected" if command == "reject" else ("needs_information" if command == "request_info" else "needs_inspection"));
            open_modal("review");
        } else { await run(command); }
    }
    async def accept_confirmation() -> None {
        if confirm == "logout" { finish_logout(); }
        elif confirm == "navigate" {
            draft = ""; note = ""; confirm = "";
            switch_view(pending_id, pending_view, pending_detail, pending_persona);
        } elif confirm == "discard" { note = ""; modal = ""; confirm = ""; }
        elif confirm == "new" { draft = ""; note = ""; confirm = ""; modal = "new"; }
        elif confirm == "review" { await run("review"); }
        elif confirm == "correct" { await run("correct"); }
        elif confirm == "inspection" { await run("inspection"); }
        elif confirm == "remove" { await run("remove"); }
        elif confirm == "upload" { await save_upload(pendingFile.current, pending_file_kind); pendingFile.current = None; confirm = ""; }
    }

    visible_cases = [c for c in cases if view == "shop" or c.customer_id == persona];
    search_results = visible_cases if not query else search_matches;
    evidence_matches = [e for e in active.evidence if e.id == evidence_id];
    modal_title = {"new": "Start a new conversation", "search": "Search your workspace", "correct": "Confirm case details", "inspection": "Record an inspection", "review": "Record a shop decision", "storage": "Your browser, your demo data", "evidence": "Evidence source"};
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
                <div className="shop-sidebar-note"><span className="section-eyebrow">ONE SHOP. EVERY DETAIL.</span><p>Give every complaint the attention it needs.</p><span className="muted tiny">Fictional inventory and sample policy. No live AI or production access control.</span></div>
            }}
            <div className="sidebar-bottom"><Button variant="ghost" className="help-button" onClick={lambda { open_modal("storage"); }}><CircleHelp size={16}/>About this demo<ChevronRight size={14}/></Button><div className="persona-control"><span className="persona-avatar">{"S" if view == "shop" else "A"}</span><div><strong>{"Shop owner" if view == "shop" else "Alex Morgan"}</strong><span>{"owner@fixora.demo" if view == "shop" else "customer@fixora.demo"}</span></div></div><Button variant="outline" className="sign-out-button" disabled={busy} onClick={logout}>Sign out</Button><span className="local-storage-caption"><span className="saved-dot"/>Demo account · Saved on this browser</span></div>
        </aside>
        <div className="workspace">
            <header className="app-header"><div className="header-left"><Button variant="ghost" size="icon" className="mobile-only" aria-label="Open navigation" onClick={lambda { side_open = True; }}><Menu size={19}/></Button><nav className="breadcrumbs" aria-label="Breadcrumb"><span>{"Shop" if view == "shop" else "Support"}</span><ChevronRight size={13}/><button onClick={lambda { if view == "shop" { navigate("", "shop", False, persona); } }}>{"Complaints" if view == "shop" else "Customer chat"}</button>{if detail and view == "shop" { <ChevronRight size={13}/><strong>{active.reference}</strong> }}</nav></div><div className="header-actions"><span className="demo-badge"><span/>Local demo</span><Button variant="ghost" className="search-trigger" aria-label="Search workspace" onClick={lambda { query = ""; open_modal("search"); }}><Search size={16}/><span>Search</span><kbd>⌘ K</kbd></Button><Button variant="ghost" size="icon" aria-label={"Switch to light mode" if dark else "Switch to dark mode"} title={"Switch to light mode" if dark else "Switch to dark mode"} onClick={toggle_theme}>{if dark { <Sun size={18}/> } else { <Moon size={18}/> }}</Button></div><div className="reading-progress" aria-hidden="true"><div ref={progressRef}/></div></header>
            {if notice { <div className="storage-banner"><span>This demo saves preferences and sample cases in your browser. No analytics trackers.</span><div><Button variant="link" size="sm" onClick={lambda { open_modal("storage"); }}>Details</Button><Button variant="outline" size="sm" onClick={dismiss_notice}>Got it</Button></div></div> }}
            {if error and not modal { <div id="workspace-error" className="feedback error-feedback" role="alert"><AlertCircle size={16}/><span>{error}</span><Button variant="ghost" size="sm" onClick={lambda { action("refresh"); }}>Reload latest</Button><Button variant="ghost" size="icon-sm" aria-label="Dismiss error" onClick={lambda { error = ""; }}><X size={14}/></Button></div> }}
            {if success { <div className="feedback success-feedback" role="status"><Check size={15}/><span>{success}</span><Button variant="ghost" size="icon-sm" aria-label="Dismiss message" onClick={lambda { success = ""; }}><X size={13}/></Button></div> }}
            <main ref={scrollRef} className="main-scroll" onScroll={on_scroll} id="main-content">
                {if not loaded { <div className="loading-screen" role="status" aria-label="Loading saved cases"><Skeleton className="h-10 w-56"/><Skeleton className="h-24 w-full"/><Skeleton className="h-24 w-3/4"/></div> } elif not active.id { <EmptyState title="Your workspace could not be loaded" text="Check the browser-storage message above, then reload the page."/> } elif view == "chat" { <ChatWorkspace c={active} draft={draft} busy={busy} upload_percent={upload_percent} error={error} onDraft={set_draft} onSend={send} onAction={action} onFile={upload} onEvidence={open_evidence} onRemove={request_remove}/> } else { <ShopDashboard cases={cases} c={active} detail={detail} busy={busy} tab={detail_tab} onTab={change_tab} draft={draft} error={error} onDraft={set_draft} onSelect={select_case} onAction={action} onEvidence={open_evidence}/> }}
            </main>
            <div className={"floating-actions " + ("detail-floating" if detail and view == "shop" else "")} aria-label="Quick actions">{if view == "chat" {
                <Button variant="outline" size="icon" aria-label="Start new complaint" title="New complaint" onClick={lambda { open_modal("new"); }}><Plus size={17}/></Button>
                if scrolled { <Button variant="outline" size="icon" aria-label="Jump to latest message" onClick={lambda { scroll_content(True); }}><ArrowDown size={17}/></Button> }
            } elif detail { <Button variant="outline" size="icon" aria-label="Return to complaint inbox" onClick={lambda { action("queue"); }}><ArrowLeft size={17}/></Button> }
            if scrolled { <Button variant="outline" size="icon" aria-label="Back to top" onClick={lambda { scroll_content(False); }}><ArrowUp size={17}/></Button> }
            }</div>
        </div>
        <Dialog open={bool(modal)} onOpenChange={close_modal}><DialogContent className={"app-dialog " + ("evidence-dialog" if modal == "evidence" else "")} onCloseAutoFocus={restore_focus}><DialogHeader><DialogTitle>{(modal_title[modal] as str) if modal_title[modal] else "Fixora"}</DialogTitle><DialogDescription>{"Search stays within this demo persona's workspace." if modal == "search" else "Interactive demo · changes are saved only on this browser."}</DialogDescription></DialogHeader>
            {if modal == "search" { <div className="search-dialog-body"><Input aria-label="Search cases and messages" autoFocus={True} value={query} onChange={lambda (e: ChangeEvent) { find_cases(e.target.value); }} placeholder="Case reference, device, complaint or message…"/><div className="search-results">{for c in search_results { <Button key={c.id} variant="ghost" className="search-result" onClick={lambda { select_case(c.id); }}><MessageSquare size={17}/><span><strong>{c.title}</strong><small>{c.reference + " · " + c.model + " · " + status_label(c.status)}</small></span><ChevronRight size={15}/></Button> }}{if len(search_results) == 0 { <EmptyState title="No matches" text="Try a different word or case reference."/> }}</div></div> }}
            {if modal == "new" { <div className="modal-fields"><Field><FieldLabel htmlFor="new-model">Your laptop model</FieldLabel><NativeSelect id="new-model" value={model} onChange={lambda (e: ChangeEvent) { model = e.target.value; }}><NativeSelectOption value="Studio 14">Studio 14 · demo model</NativeSelectOption><NativeSelectOption value="Pro 15">Pro 15 · demo model</NativeSelectOption><NativeSelectOption value="Air 13">Air 13 · demo model</NativeSelectOption></NativeSelect></Field><Field><FieldLabel htmlFor="scenario">Sample assessment scenario</FieldLabel><NativeSelect id="scenario" value={scenario} onChange={lambda (e: ChangeEvent) { scenario = e.target.value; }}><NativeSelectOption value="complete">Complete evidence → owner review</NativeSelectOption><NativeSelectOption value="conflict">Conflicting model → clarification</NativeSelectOption><NativeSelectOption value="inspection">Uncertain fault → inspection</NativeSelectOption><NativeSelectOption value="auto">Verified fixture → automatic approval</NativeSelectOption><NativeSelectOption value="rejected">Expired period → warranty declined</NativeSelectOption><NativeSelectOption value="no_stock">Compatible part out of stock</NativeSelectOption><NativeSelectOption value="missing_charger">Reported missing charger → sample stock</NativeSelectOption><NativeSelectOption value="replacement">Replacement component → sample stock</NativeSelectOption><NativeSelectOption value="uncertain_compatibility">Uncertain part compatibility → confirm details</NativeSelectOption><NativeSelectOption value="inventory_failure">Inventory check failure → retry</NativeSelectOption><NativeSelectOption value="failure">Technical timeout → retry</NativeSelectOption></NativeSelect></Field><div className="notice-box"><ShieldCheck size={17}/><span>Your chosen scenario supplies the sample findings. Uploads are local previews, not AI-analysed evidence.</span></div><DialogFooter><Button disabled={busy} onClick={lambda { run("create"); }}>Start conversation<Plus size={15}/></Button></DialogFooter></div> }}
            {if modal == "correct" { <div className="modal-fields"><Field><FieldLabel htmlFor="correct-model">Confirmed laptop model</FieldLabel><NativeSelect id="correct-model" value={model} onChange={lambda (e: ChangeEvent) { model = e.target.value; }}><NativeSelectOption value="Studio 14">Studio 14</NativeSelectOption><NativeSelectOption value="Pro 15">Pro 15</NativeSelectOption><NativeSelectOption value="Air 13">Air 13</NativeSelectOption></NativeSelect></Field><Field><FieldLabel htmlFor="correction-note">What changed? *</FieldLabel><Textarea id="correction-note" aria-invalid={bool(error) and not note.strip()} aria-describedby={"workspace-error" if error else None} value={note} onChange={lambda (e: ChangeEvent) { note = e.target.value; error = ""; }} placeholder="Explain the correction and where the correct detail comes from."/></Field><p className="muted small">A new revision requires reassessment. Previous findings and decisions remain in history.</p><DialogFooter><Button disabled={busy} onClick={lambda { if note.strip() { request_confirmation("correct"); } else { error = "Explain the correction before saving."; } }}>Save correction</Button></DialogFooter></div> }}
            {if modal == "inspection" { <div className="modal-fields"><Field><FieldLabel htmlFor="diagnosis">Supported inspection finding *</FieldLabel><NativeSelect id="diagnosis" value={diagnosis} onChange={lambda (e: ChangeEvent) { diagnosis = e.target.value; }}><NativeSelectOption value="">Select a finding</NativeSelectOption><NativeSelectOption value="Charging connector failure confirmed">Charging connector failure confirmed</NativeSelectOption><NativeSelectOption value="Further diagnostics required">Further diagnostics required</NativeSelectOption><NativeSelectOption value="No fault reproduced">No fault reproduced</NativeSelectOption></NativeSelect></Field><Field><FieldLabel htmlFor="inspection-note">Internal inspection notes *</FieldLabel><Textarea id="inspection-note" aria-invalid={bool(error) and not note.strip()} aria-describedby={"workspace-error" if error else None} value={note} onChange={lambda (e: ChangeEvent) { note = e.target.value; error = ""; }} placeholder="Record the observed finding and the checks performed."/></Field><p className="muted small">Internal notes stay in the shop view. The revised case must be reassessed.</p><DialogFooter><Button disabled={busy} onClick={lambda { if diagnosis and note.strip() { request_confirmation("inspection"); } else { error = "Choose a finding and enter inspection notes."; } }}>Save inspection</Button></DialogFooter></div> }}
            {if modal == "review" { <div className="modal-fields"><div className="review-choice"><span className="section-eyebrow">{active.reference + " · REVISION " + str(active.revision)}</span><h3>{status_label(review_action)}</h3><p>{"This will be recorded as an explicit owner override of the current outcome." if active.status in ["approved", "rejected"] else "Your decision and reason will be visible in the customer's conversation."}</p></div><Field><FieldLabel htmlFor="review-note">Reason / customer-facing response *</FieldLabel><Textarea id="review-note" aria-invalid={bool(error) and not note.strip()} aria-describedby={"workspace-error" if error else None} value={note} onChange={lambda (e: ChangeEvent) { note = e.target.value; error = ""; }} placeholder="Explain the decision and the customer's next step."/></Field><Button variant="link" size="sm" onClick={lambda { review_action = "needs_inspection"; }}>Request a physical inspection instead</Button><DialogFooter><Button disabled={busy} onClick={lambda { if note.strip() { request_confirmation("review"); } else { error = "Enter a reason or customer-facing response."; } }}>Review decision<ChevronRight size={14}/></Button></DialogFooter></div> }}
            {if modal == "storage" { <div className="storage-details"><p>Fixora is a browser-local interactive prototype. Sample conversations, previews, revisions, and shop decisions are saved in IndexedDB. Your theme and dismissal preference are saved locally.</p><p>No AI model, MongoDB connection, analytics tracker, or production authentication is active. Dummy accounts select the customer or shop view; they do not enforce access control.</p><p>Clearing this site's browser storage removes its local demo data. Images shown as illustrative devices are generated artwork, separate from case evidence.</p><p className="muted small">Case timestamps use UTC. The fictional sample policy uses Asia/Colombo for its evaluation date.</p></div> }}
            {if modal == "evidence" { <div className="evidence-viewer">{if evidence_id == "policy" { <div className="policy-source"><h3>Fictional shop policy v1</h3><p><strong>W-01 · Period:</strong> 12 calendar months from purchase, with the final date inclusive. These demo dates are fixture values.</p><p><strong>R-02 · Repair:</strong> A compatible charging connector may be proposed after a supported diagnosis. Unknown causes require inspection.</p><p><strong>A-01 · Automatic sample approval:</strong> Only the verified-diagnosis fixture includes all configured sample approval conditions.</p><p>A passed date check alone does not establish coverage. Declining warranty does not decline paid repair service.</p></div> } elif len(evidence_matches) > 0 { <figure><img src={evidence_matches[0].preview} alt={evidence_matches[0].name}/><figcaption>{evidence_matches[0].name + " · " + evidence_matches[0].mime}</figcaption></figure> } else { <EmptyState title="Sample source reference" text="This is a fixture finding. No corresponding real customer evidence has been analysed."/> }}</div> }}
            {if error and modal { <div id="workspace-error" className="inline-error" role="alert"><AlertCircle size={15}/><span>{error}</span><Button variant="outline" size="sm" onClick={lambda { run("refresh"); }}>Load latest case</Button></div> }}
        </DialogContent></Dialog>
        <AlertDialog open={bool(confirm)} onOpenChange={lambda (opened: bool) { if not opened { confirm = ""; } }}><AlertDialogContent className="confirmation-dialog" onCloseAutoFocus={restore_confirmation}><AlertDialogHeader><AlertDialogTitle>{"Discard unsaved changes?" if confirm in ["navigate", "discard", "new", "logout"] else ("Remove this attachment?" if confirm == "remove" else ("Confirm shop decision" if confirm == "review" else "Create a revised assessment?"))}</AlertDialogTitle><AlertDialogDescription>{"Your unsent message or notes will be discarded. Saved cases remain available." if confirm in ["navigate", "discard", "new", "logout"] else ("This saves a new case revision. Previous decisions remain as history and must not be treated as current approval." if confirm in ["correct", "inspection", "remove", "upload"] else "The recorded outcome and reason will be added to the decision history and published to this customer's chat. This demo does not authorize payments or reserve stock.")}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={busy}>Keep editing</AlertDialogCancel><AlertDialogAction disabled={busy} onClick={lambda (e: MouseEvent) { e.preventDefault(); accept_confirmation(); }}>{if busy { <LoaderCircle size={14} className="spin"/> }}Confirm</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    </div>;
}
