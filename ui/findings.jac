import from "lucide-react" { ShieldCheck, Package, ArrowUpRight, Info, FileText }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.ui.badge { Badge }
import from .models { CaseRecord }
import from .gateway { assessment }
import from .pieces { CopyButton }
import from .parts { PartsAvailability }

cl def money(amount: int) -> str { return f"USD {amount / 100:.2f}"; }

def:pub Findings(c: CaseRecord, compact: bool, busy: bool, onSource: Callable[[str], None], onAction: Callable[[str], None]) -> JsxElement {
    a = assessment(c);
    invoices = [e for e in c.evidence if e.kind == "invoice"];
    photos = [e for e in c.evidence if e.kind == "product"];
    invoice_id = invoices[0].id if len(invoices) > 0 else "";
    photo_id = photos[0].id if len(photos) > 0 else "";
    summary = "Assessment for " + c.reference + ": " + a.coverage + ". " + a.rationale + " " + a.next_action;
    return <div className={"findings " + ("findings-compact" if compact else "")}>
        <Card className="result-card">
            <CardHeader className="result-header">
                <div className="result-icon"><ShieldCheck size={20}/></div>
                <div><CardTitle>Here's what we found</CardTitle><CardDescription>{c.analysis_mode}</CardDescription></div>
                <CopyButton text={summary} label="Copy assessment summary"/>
            </CardHeader>
            <CardContent>
                <div className="coverage-line"><span>Warranty assessment</span><Badge variant="secondary" className="coverage-badge">{a.coverage}</Badge></div>
                <p>{a.rationale}</p>
                <div className="date-pair"><div><span>Purchased</span><strong>{a.purchase_date}</strong></div><div><span>Warranty expiry</span><strong>{a.expiry_date}</strong></div></div>
                <p className="muted small">{a.eligibility}</p>
                <div className="source-links"><Button variant="ghost" size="sm" onClick={lambda { onSource(invoice_id); }}><FileText size={13}/>Invoice source<ArrowUpRight size={12}/></Button><Button variant="ghost" size="sm" onClick={lambda { onSource("policy"); }}>Saved policy<ArrowUpRight size={12}/></Button></div>
            </CardContent>
        </Card>
        {if not compact {
            <Card className="detail-card"><CardHeader><CardTitle>Invoice extraction</CardTitle><CardDescription>Saved extraction from the attached invoice</CardDescription></CardHeader><CardContent>
                <dl className="fact-grid"><div><dt>Invoice</dt><dd>{a.invoice}</dd></div><div><dt>Product</dt><dd>{c.model}</dd></div><div><dt>Serial</dt><dd>{a.serial}</dd></div><div><dt>Seller</dt><dd>{a.seller}</dd></div><div><dt>Invoice total</dt><dd>{a.invoice_total}</dd></div><div><dt>Policy</dt><dd>{a.policy}</dd></div></dl>
                <Button variant="link" size="sm" onClick={lambda { onSource(invoice_id); }}>View invoice evidence<ArrowUpRight size={13}/></Button>
            </CardContent></Card>
            <Card className="detail-card"><CardHeader><CardTitle>Observations & limitations</CardTitle></CardHeader><CardContent><p>{a.observation}</p><Button variant="link" size="sm" onClick={lambda { onSource(photo_id); }}>View product evidence<ArrowUpRight size={13}/></Button><div className="notice-box"><Info size={16}/><span>{a.limitation}</span></div></CardContent></Card>
        }}
        <PartsAvailability c={c} compact={compact} busy={busy} onAction={onAction}/>
        <div className="next-step"><span className="section-eyebrow">NEXT STEP</span><p>{a.next_action}</p></div>
    </div>;
}
