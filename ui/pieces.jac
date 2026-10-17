import from "lucide-react" { Copy, Check, AlertCircle, FileImage, FileText, CheckCircle2, LoaderCircle, Clock }
import from ..components.ui.button { Button }
import from ..components.ui.badge { Badge }
import from .models { CaseRecord, Evidence }
import from .gateway { status_label }

def:pub StatusPill(status: str) -> JsxElement {
    return <Badge variant="secondary" className={"status-pill status-" + status}><span className="status-dot"/>{status_label(status)}</Badge>;
}

def:pub CopyButton(text: str, label: str = "Copy response") -> JsxElement {
    has feedback: str = "";
    async def copy_text() -> None {
        try { await navigator.clipboard.writeText(text); feedback = "Copied"; }
        except Exception { feedback = "Copy unavailable"; }
    }
    return <Button variant="ghost" size="sm" className="copy-button" aria-label={label} title={label} onClick={copy_text}>
        {if feedback == "Copied" { <Check size={13}/> } else { <Copy size={13}/> }}
        <span aria-live="polite">{feedback}</span>
    </Button>;
}

def:pub StageActivity(c: CaseRecord) -> JsxElement {
    stages = ["Document", "Vision", "Coverage", "Repair & parts", "Resolution"];
    return <section className="stage-panel" aria-label="Server assessment stages">
        <div className="section-eyebrow"><span>ASSESSMENT ACTIVITY</span><span>{"Saved · " + str(c.stage) + "/5 stages"}</span></div>
        <ol className="stage-list">
            {for (i, name) in enumerate(stages) {
                <li key={name} className={"stage-item " + ("stage-done" if i < c.stage else "")}>
                    <span className="stage-circle">{if i < c.stage { <Check size={12}/> } elif i == c.stage and c.status == "processing" { <LoaderCircle size={12} className="spin"/> } else { <span>{i + 1}</span> }}</span>
                    <span>{name}</span>
                </li>
            }}
        </ol>
        {if c.status == "failed" { <p className="inline-error"><AlertCircle size={14}/>{c.failure or "The specialist failed. Your evidence is saved; retry to resume."}</p> }}
        {if c.status == "processing" { <p className="muted small"><Clock size={13}/>A specialist is running or ready to continue. Progress is saved after each stage.</p> }}
    </section>;
}

def:pub EvidenceStrip(evidence: list[Evidence], onOpen: Callable[[str], None], onRemove: Callable[[str], None] | None = None) -> JsxElement {
    return <div className="evidence-strip">
        {for e in evidence {
            <div key={e.id} className="evidence-item">
                <button className="evidence-thumb" onClick={lambda { onOpen(e.id); }} aria-label={"Open " + e.name}>
                    {if e.preview { <img src={e.preview} alt={e.name} loading="lazy"/> } else { <FileImage size={22}/> }}
                </button>
                <div><button className="text-link evidence-name" onClick={lambda { onOpen(e.id); }}>{e.name}</button><span className="muted tiny">{e.kind + " · " + str(round(e.size / 1024)) + " KB"}</span></div>
                {if onRemove { <Button variant="ghost" size="sm" className="remove-evidence" onClick={lambda { onRemove(e.id); }}>Remove</Button> }}
            </div>
        }}
    </div>;
}

def:pub EmptyState(title: str, text: str) -> JsxElement {
    return <div className="empty-state"><FileImage size={28}/><h3>{title}</h3><p>{text}</p></div>;
}
