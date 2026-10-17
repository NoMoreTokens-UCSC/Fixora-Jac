import from "lucide-react" { ArrowUp, Paperclip, FileText, ImagePlus, ShieldCheck, ArrowRight, Info, LoaderCircle, MessageSquare }
import from ..components.ui.button { Button }
import from ..components.ui.textarea { Textarea }
import from ..components.ui.progress { Progress }
import from .models { CaseRecord }
import from .pieces { StatusPill, CopyButton, StageActivity, EvidenceStrip }
import from .findings { Findings }
import from .brand { BrandMark }
import from .motion { TitleMotion }

def:pub ChatWorkspace(c: CaseRecord, draft: str, busy: bool, upload_percent: int, error: str, onDraft: Callable[[str], None], onSend: Callable[[], None], onAction: Callable[[str], None], onFile: Callable[[any, str], None], onEvidence: Callable[[str], None], onRemove: Callable[[str], None]) -> JsxElement {
    has invoiceInput: Ref[HTMLInputElement] = Ref();
    has photoInput: Ref[HTMLInputElement] = Ref();
    def submit(e: FormEvent) { e.preventDefault(); if not busy { onSend(); } }
    def key_down(e: KeyboardEvent) {
        browser_event: any = e;
        native_event: any = browser_event.nativeEvent;
        if e.key == "Enter" and not e.shiftKey and not native_event.isComposing { e.preventDefault(); if not busy { onSend(); } }
    }
    def invoice_changed(e: ChangeEvent) {
        files: any = e.target.files;
        if files and files.length > 0 { onFile(files[0], "invoice"); }
        e.target.value = "";
    }
    def photo_changed(e: ChangeEvent) {
        files: any = e.target.files;
        if files and files.length > 0 { onFile(files[0], "photo"); }
        e.target.value = "";
    }
    return <div className="chat-layout">
        <div className="chat-thread">
            <div className="chat-intro"><div className="eyebrow"><span className="violet-dot"/>YOUR LAPTOP, IN GOOD HANDS</div><h1><TitleMotion>A little help for{" "}<br/>your laptop.</TitleMotion></h1><p>Tell us what's wrong. We'll help you find the next step.</p></div>
            <div className="conversation-heading"><span>{c.title}</span><div className="conversation-heading-actions"><Button variant="ghost" size="sm" onClick={lambda { onAction("correct"); }}>Edit details</Button><StatusPill status={c.status}/></div></div>
            <div className="day-divider"><span>YOUR SAVED CONVERSATION</span></div>
            <div className="message-list" role="log" aria-label="Complaint conversation" aria-live="polite" aria-relevant="additions">
                {for m in c.messages {
                    if not m.internal {
                        <article key={m.id} className={"message-row message-" + m.role}>
                            <div className="message-avatar">{if m.role == "customer" { <span>{c.customer[:1]}</span> } elif m.role == "shop" { <ShieldCheck size={16}/> } else { <BrandMark/> }}</div>
                            <div className="message-body"><div className="message-name">{c.customer.split(" ")[0] if m.role == "customer" else ("Your shop" if m.role == "shop" else "Fixora assistant")}<time>{m.at[11:16]}</time></div><div className="message-bubble">{m.text}</div>{if m.role != "customer" { <CopyButton text={m.text}/> }}</div>
                        </article>
                    }
                }}
            </div>
            {if len(c.evidence) > 0 { <section className="chat-evidence"><div className="section-eyebrow">ATTACHED TO THIS CASE</div><EvidenceStrip evidence={c.evidence} onOpen={onEvidence} onRemove={onRemove}/></section> }}
            {if c.stage > 0 { <StageActivity c={c}/> }}
            {if c.stage >= 3 { <Findings c={c} compact={True} onSource={onEvidence}/> }}
            {if c.status == "needs_information" or c.status == "needs_inspection" {
                <div className="clarification-card"><Info size={18}/><div><strong>{"Let's confirm the details" if c.status == "needs_information" else "A closer look is needed"}</strong><p>{"Confirm the correct model and explain the correction. You can remove an attachment and add a clearer or matching image." if c.status == "needs_information" else "A photo cannot establish this fault. The shop can record findings after a physical inspection."}</p><Button variant="outline" onClick={lambda { onAction("correct"); }}>Confirm details<ArrowRight size={14}/></Button></div></div>
            }}
            {if c.status == "draft" or c.status == "processing" or c.status == "failed" {
                <div className="assessment-cta"><div><strong>{"Ready when you are" if c.status == "draft" else "Pick up where you left off"}</strong><p>One bounded sample stage at a time. Your progress is saved.</p></div><Button disabled={busy} onClick={lambda { onAction("assess"); }}>{if busy { <LoaderCircle size={15} className="spin"/> }}{"Assess complaint" if c.status == "draft" else ("Retry assessment" if c.status == "failed" else "Resume assessment")}<ArrowRight size={14}/></Button></div>
            }}
            {if busy { <div className="pending-message" role="status"><span className="typing-dot"/><span className="typing-dot"/><span className="typing-dot"/><span>Saving your next step…</span></div> }}
            <div id="thread-end"/>
        </div>
        <div className="composer-dock">
            {if upload_percent >= 0 { <div className="upload-progress" role="status"><span>{"Saving image locally · " + str(upload_percent) + "%"}</span><Progress value={upload_percent} aria-label="Image save progress"/></div> }}
            <form className="composer" onSubmit={submit}>
                <label className="sr-only" htmlFor="chat-message">Message Fixora</label>
                <Textarea id="chat-message" value={draft} onChange={lambda (e: ChangeEvent) { onDraft(e.target.value); }} onKeyDown={key_down} placeholder="Tell us about your laptop…" maxLength={4000} className="message-input" disabled={busy} aria-invalid={bool(error)} aria-describedby={"workspace-error" if error else None}/>
                <div className="composer-tools"><div className="attachment-actions"><input ref={invoiceInput} type="file" accept="image/jpeg,image/png" className="sr-only" aria-label="Choose invoice image" onChange={invoice_changed}/><input ref={photoInput} type="file" accept="image/jpeg,image/png" className="sr-only" aria-label="Choose product photo" onChange={photo_changed}/><Button type="button" variant="ghost" size="sm" disabled={busy} onClick={lambda { if invoiceInput.current { invoiceInput.current.click(); } }}><FileText size={15}/><span>Invoice</span></Button><Button type="button" variant="ghost" size="sm" disabled={busy} onClick={lambda { if photoInput.current { photoInput.current.click(); } }}><ImagePlus size={15}/><span>Photo</span></Button><span className="upload-hint">JPG / PNG · 5 MB</span></div><Button type="submit" className="send-button" aria-label="Send message" disabled={busy}>{if busy { <LoaderCircle size={18} className="spin"/> } else { <ArrowUp size={18}/> }}</Button></div>
            </form>
            <p className="composer-caption"><ShieldCheck size={12}/>Local demo · Sample findings, not a live diagnosis.<span>Enter to send · Shift+Enter for a new line</span></p>
        </div>
    </div>;
}
