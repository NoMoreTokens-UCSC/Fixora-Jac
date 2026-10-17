import from "lucide-react" { ArrowUpRight, ArrowLeft, ChevronRight, Search, ClipboardList, Clock, ShieldCheck, TriangleAlert, MessageSquare, FileImage, Check, X, RefreshCw, Wrench, Info }
import from ..components.ui.button { Button }
import from ..components.ui.input { Input }
import from ..components.ui.textarea { Textarea }
import from ..components.ui.tabs { Tabs, TabsList, TabsTrigger, TabsContent }
import from .models { CaseRecord }
import from .gateway { model_image, status_label }
import from .pieces { StatusPill, CopyButton, StageActivity, EvidenceStrip, EmptyState }
import from .findings { Findings }
import from .imagery { device_photo }
import from .motion { TitleMotion }

def:pub ShopDashboard(cases: list[CaseRecord], c: CaseRecord, detail: bool, busy: bool, tab: str, onTab: Callable[[str], None], draft: str, error: str, onDraft: Callable[[str], None], onSelect: Callable[[str], None], onAction: Callable[[str], None], onEvidence: Callable[[str], None]) -> JsxElement {
    has filter: str = "all";
    has query: str = "";
    def reply(e: FormEvent) { e.preventDefault(); if not busy { onAction("shop_reply"); } }
    pending = len([v for v in cases if v.status == "completed"]);
    attention = len([v for v in cases if v.status in ["needs_information", "needs_inspection", "failed"]]);
    resolved = len([v for v in cases if v.status == "draft"]);
    filtered = [v for v in cases if (filter == "all" or (filter == "review" and v.status == "completed") or (filter == "attention" and v.status in ["needs_information", "needs_inspection", "failed"]) or (filter == "resolved" and v.status == "draft")) and (not query or query.lower() in (v.reference + " " + v.title + " " + v.model + " " + v.customer).lower())];
    if not detail {
        return <div className="dashboard-overview">
            <div className="page-heading"><div><div className="eyebrow">SHOP WORKSPACE</div><h1><TitleMotion>A clear view of every repair.</TitleMotion></h1><p>Your complaints, evidence, and next decisions. All in one place.</p></div><Button variant="outline" onClick={lambda { onAction("refresh"); }} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
            <section className="shop-banner"><div className="shop-banner-copy"><span className="eyebrow">CARE THAT GOES BEYOND THE COUNTER</span><h2>Good repairs start<br/>with the right details.</h2><p>Review the evidence. Make the next step clear.</p></div><div className="shop-photo" role="img" aria-label="Generated illustration of a laptop repair workbench"/><span className="image-caption">Illustrative shop image</span></section>
            <section className="stats-grid" aria-label="Complaint summary">
                <div className="stat"><div><span>All complaints</span><ClipboardList size={17}/></div><strong>{len(cases)}</strong><small>Saved in MongoDB</small></div>
                <div className="stat"><div><span>Assessment ready</span><Clock size={17}/></div><strong>{pending}</strong><small>Provisional assessment complete</small></div>
                <div className="stat"><div><span>Need attention</span><TriangleAlert size={17}/></div><strong>{attention}</strong><small>Information, inspection or retry</small></div>
                <div className="stat"><div><span>Drafts</span><ShieldCheck size={17}/></div><strong>{resolved}</strong><small>Ready for evidence or reassessment</small></div>
            </section>
            <section className="queue-panel"><div className="queue-title"><div><h2>Complaint inbox<span>{len(cases)}</span></h2><p>Every conversation, with the context you need.</p></div><div className="queue-search"><Search size={15}/><Input aria-label="Filter complaints" value={query} onChange={lambda (e: ChangeEvent) { query = e.target.value; }} placeholder="Search complaints…"/></div></div>
                <div className="queue-filters" role="group" aria-label="Filter complaint status">{for (key, label) in [("all", "All complaints"), ("review", "Assessment ready"), ("attention", "Needs attention"), ("resolved", "Drafts")] { <Button key={key} variant="ghost" aria-pressed={filter == key} className={"filter-button " + ("active" if filter == key else "")} onClick={lambda { filter = key; }}>{label}</Button> }}</div>
                <div className="queue-column-head"><span>COMPLAINT / CUSTOMER</span><span>DEVICE</span><span>STATUS</span><span>REFERENCE</span></div>
                <div className="case-queue" role="list" aria-label="Complaints">{for v in filtered { <div key={v.id} role="listitem"><button className="case-row" onClick={lambda { onSelect(v.id); }}><div className="case-main"><span className="customer-avatar">{v.customer[:1]}</span><div><strong>{v.title}</strong><span>{v.customer}</span></div></div><span className="case-device">{v.model}</span><StatusPill status={v.status}/><span className="case-reference">{v.reference}<ChevronRight size={16}/></span></button></div> }}</div>
                {if len(filtered) == 0 { <EmptyState title="No complaints found" text="Try another search or status filter."/> }}
            </section>
            <section className="devices-section"><div className="section-eyebrow"><span>SEEDED CATALOGUE DEVICES</span><span>Generated illustrative photography</span></div><div className="device-cards">{for model in ["Fixora Demo FD-100", "Fixora Demo FD-200", "Fixora Demo FD-300"] { <div key={model} className="device-card"><img className="device-photo" src={device_photo(model)} loading="lazy" width={90} height={65} alt={"Illustrative unbranded laptop for " + model}/><div><strong>{model}</strong><span>Fictional demo model</span></div></div> }}</div></section>
        </div>;
    }
    return <div className="case-detail">
        <div className="detail-heading"><div><Button variant="ghost" size="sm" onClick={lambda { onAction("queue"); }}><ArrowLeft size={14}/>Complaint inbox</Button><div className="detail-reference"><span>{c.reference}</span><CopyButton text={c.reference} label="Copy case reference"/><StatusPill status={c.status}/></div><h1><TitleMotion key={c.id}>{c.title}</TitleMotion></h1><p>{c.customer + " · " + c.model + " · Revision " + str(c.revision)}</p></div><div className={"detail-device device-photo " + model_image(c.model)} role="img" aria-label="Illustrative laptop, not customer evidence"/></div>
        <Tabs value={tab} onValueChange={onTab} className="detail-tabs"><TabsList className="detail-tab-list"><TabsTrigger value="assessment">Assessment</TabsTrigger><TabsTrigger value="conversation">Conversation</TabsTrigger><TabsTrigger value="evidence">Evidence</TabsTrigger><TabsTrigger value="history">Decision history</TabsTrigger></TabsList>
            <TabsContent value="assessment"><StageActivity c={c}/>{if c.backend and c.backend.assessment { <Findings c={c} compact={False} onSource={onEvidence}/> } else { <EmptyState title="Ready for a fresh assessment" text="Run the assessment to obtain findings for the current inputs."/> }}</TabsContent>
            <TabsContent value="conversation"><section className="owner-conversation" aria-label="Conversation with customer">{for m in c.messages { <article key={m.id} className={"owner-message " + ("internal-message" if m.internal else "")}><div><strong>{"Internal shop note" if m.internal else (c.customer if m.role == "customer" else ("Shop" if m.role == "shop" else "Fixora assistant"))}</strong><time>{m.at[:10] + " · " + m.at[11:16]}</time></div><p>{m.text}</p><CopyButton text={m.text}/></article> }}</section><p className="notice-box">Shop replies are not available in the backend yet. Customer updates are saved as case-description revisions.</p></TabsContent>
            <TabsContent value="evidence"><div className="evidence-page-heading"><h2>Evidence attached to this case</h2><p>Open an image to inspect its source. Generated laptop imagery elsewhere is illustrative.</p></div>{if len(c.evidence) > 0 { <EvidenceStrip evidence={c.evidence} onOpen={onEvidence}/> } else { <EmptyState title="No evidence yet" text="The customer can attach an invoice and product photos in chat."/> }}</TabsContent>
            <TabsContent value="history">{if len(c.decisions) == 0 { <EmptyState title="No decisions recorded" text="Approval and decision-history APIs are not available yet. Current specialist results are saved with the case."/> } else { <div className="decision-timeline">{for d in c.decisions { <article key={d.id} className="decision-entry"><span className="timeline-marker"><ShieldCheck size={16}/></span><div><div className="decision-entry-title"><strong>{status_label(d.action)}</strong><span>{d.origin + " · revision " + str(d.revision)}</span>{if d.revision != c.revision { <span className="history-label">Previous revision</span> }}</div><p>{d.reason}</p><small>{d.scope + " · " + d.at[:10] + " " + d.at[11:16] + " UTC"}</small></div></article> }}</div> }}</TabsContent>
        </Tabs>
        <div className="owner-action-bar"><div><span className="section-eyebrow">NEXT STEP</span><strong>{"Review the saved provisional assessment" if c.status == "completed" else "Gather details or assess the current revision"}</strong></div><div className="owner-actions"><Button variant="outline" disabled={busy} onClick={lambda { onAction("correct"); }}>Correct details</Button>{if c.status in ["draft", "failed", "processing"] { <Button disabled={busy} onClick={lambda { onAction("assess"); }}>Resume assessment</Button> }}<Button disabled={True}>Approval unavailable</Button></div></div>
        <p className="muted tiny owner-note">Inspection records, owner replies and approval decisions need additional backend APIs. Results are provisional; no stock is reserved and no payment is authorized.</p>
    </div>;
}
