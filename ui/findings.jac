import from "lucide-react" { ShieldCheck, Package, ArrowUpRight, Info, FileText }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.ui.badge { Badge }
import from .models { CaseRecord }
import from .gateway { assessment }
import from .pieces { CopyButton }

cl def money(amount: int) -> str { return f"USD {amount / 100:.2f}"; }

def:pub Findings(c: CaseRecord, compact: bool, onSource: Callable[[str], None]) -> JsxElement {
    a = assessment(c);
    invoice_id = c.evidence[0].id if len(c.evidence) > 0 else "sample";
    photo_id = c.evidence[1].id if len(c.evidence) > 1 else "sample";
    summary = "Sample assessment for " + c.reference + ": " + a.coverage + ". " + a.rationale + " " + a.next_action;
    return <div className={"findings " + ("findings-compact" if compact else "")}>
        <Card className="result-card">
            <CardHeader className="result-header">
                <div className="result-icon"><ShieldCheck size={20}/></div>
                <div><CardTitle>Here's what we found</CardTitle><CardDescription>Sample assessment · fictional shop policy</CardDescription></div>
                <CopyButton text={summary} label="Copy assessment summary"/>
            </CardHeader>
            <CardContent>
                <div className="coverage-line"><span>Warranty assessment</span><Badge variant="secondary" className="coverage-badge">{a.coverage}</Badge></div>
                <p>{a.rationale}</p>
                <div className="date-pair"><div><span>Purchased</span><strong>{a.purchase_date}</strong></div><div><span>Sample expiry</span><strong>{a.expiry_date}</strong></div></div>
                <p className="muted small">{a.eligibility}</p>
                <div className="source-links"><Button variant="ghost" size="sm" onClick={lambda { onSource(invoice_id); }}><FileText size={13}/>Invoice source<ArrowUpRight size={12}/></Button><Button variant="ghost" size="sm" onClick={lambda { onSource("policy"); }}>Policy W-01 / R-02<ArrowUpRight size={12}/></Button></div>
            </CardContent>
        </Card>
        {if not compact {
            <Card className="detail-card"><CardHeader><CardTitle>Invoice extraction</CardTitle><CardDescription>Fixed sample values, not live image extraction</CardDescription></CardHeader><CardContent>
                <dl className="fact-grid"><div><dt>Invoice</dt><dd>{a.invoice}</dd></div><div><dt>Product</dt><dd>{c.model}</dd></div><div><dt>Serial</dt><dd>{a.serial}</dd></div><div><dt>Seller</dt><dd>{a.seller}</dd></div><div><dt>Invoice total</dt><dd>USD 899.00 · sample</dd></div><div><dt>Policy</dt><dd>Demo shop policy v1</dd></div></dl>
                <Button variant="link" size="sm" onClick={lambda { onSource(invoice_id); }}>View invoice evidence<ArrowUpRight size={13}/></Button>
            </CardContent></Card>
            <Card className="detail-card"><CardHeader><CardTitle>Observations & limitations</CardTitle></CardHeader><CardContent><p>{a.observation}</p><Button variant="link" size="sm" onClick={lambda { onSource(photo_id); }}>View product evidence<ArrowUpRight size={13}/></Button><div className="notice-box"><Info size={16}/><span>{a.limitation}</span></div></CardContent></Card>
        }}
        <Card className="detail-card repair-card"><CardHeader><div className="flex items-center gap-2"><Package size={17}/><CardTitle>Repair & compatible parts</CardTitle></div><CardDescription>{"Owner finding recorded" if c.inspection else "Provisional · diagnosis must be confirmed"}</CardDescription></CardHeader><CardContent>
            <strong className="repair-title">{a.repair}</strong><p className="muted small">{a.part}</p>
            <div className="part-stock"><span className={"stock-dot " + ("out" if a.stock == 0 else "")}/><span>{str(a.stock) + " in stock · seeded availability" if a.stock > 0 else "Out of stock · arrival unknown"}</span></div>
            <dl className="cost-lines"><div><dt>Compatible part</dt><dd>{money(a.part_minor)}</dd></div><div><dt>Labour</dt><dd>{money(a.labour_minor)}</dd></div><div className="cost-total"><dt>Shop repair cost</dt><dd>{money(a.part_minor + a.labour_minor)}</dd></div></dl>
            <p className="muted tiny">Illustrative cost snapshot, not a firm quote. Customer payable remains unresolved until the shop confirms coverage. Stock is not reserved.</p>
        </CardContent></Card>
        <div className="next-step"><span className="section-eyebrow">NEXT STEP</span><p>{a.next_action}</p></div>
    </div>;
}
