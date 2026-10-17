import from "lucide-react" { ShieldCheck, Package, ArrowUpRight, Info, FileText }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.ui.badge { Badge }
import from .models { CaseRecord }
import from .gateway { assessment, money }
import from .pieces { CopyButton }

def:pub Findings(c: CaseRecord, compact: bool, onSource: Callable[[str], None]) -> JsxElement {
    a = assessment(c);
    invoices = [e for e in c.evidence if e.kind == "invoice"];
    photos = [e for e in c.evidence if e.kind == "photo"];
    summary = "Assessment for " + c.reference + ": " + a.coverage + ". " + a.rationale + " " + a.next_action;
    return <div className={"findings " + ("findings-compact" if compact else "")}>
        <Card className="result-card"><CardHeader className="result-header"><div className="result-icon"><ShieldCheck size={20}/></div><div><CardTitle>Here's what we found</CardTitle><CardDescription>{"Saved server results · " + ("Fixture replay; no live inference" if a.mode == "demo_fixture" else ("Live model extraction + catalogue rules" if a.mode == "live_model" else a.mode))}</CardDescription></div><CopyButton text={summary} label="Copy assessment summary"/></CardHeader><CardContent>
            <div className="coverage-line"><span>Warranty assessment</span><Badge variant="secondary" className="coverage-badge">{a.coverage}</Badge></div><p>{a.rationale}</p>
            <div className="date-pair"><div><span>Purchased</span><strong>{a.purchase_date}</strong></div><div><span>Policy expiry</span><strong>{a.expiry_date}</strong></div></div><p className="muted small">{a.eligibility}</p>
            <div className="source-links">{if len(invoices) > 0 { <Button variant="ghost" size="sm" onClick={lambda { onSource(invoices[0].id); }}><FileText size={13}/>Invoice source<ArrowUpRight size={12}/></Button> }}<Button variant="ghost" size="sm" onClick={lambda { onSource("policy"); }}>Applied policy<ArrowUpRight size={12}/></Button></div>
        </CardContent></Card>
        <Card className="detail-card"><CardHeader><CardTitle>Invoice extraction</CardTitle><CardDescription>Fields returned by the document specialist</CardDescription></CardHeader><CardContent><dl className="fact-grid"><div><dt>Invoice</dt><dd>{a.invoice}</dd></div><div><dt>Selected product</dt><dd>{c.model}</dd></div><div><dt>Serial</dt><dd>{a.serial}</dd></div><div><dt>Seller</dt><dd>{a.seller}</dd></div><div><dt>Invoice total</dt><dd>{a.invoice_total}</dd></div><div><dt>Policy</dt><dd>{a.policy}</dd></div></dl></CardContent></Card>
        <Card className="detail-card"><CardHeader><CardTitle>Observations & limitations</CardTitle></CardHeader><CardContent><p>{a.observation}</p>{for photo in photos { <Button key={photo.id} variant="link" size="sm" onClick={lambda { onSource(photo.id); }}>View {photo.name}<ArrowUpRight size={13}/></Button> }}<div className="notice-box"><Info size={16}/><span>{a.limitation}</span></div></CardContent></Card>
        {if len(a.options) == 0 { <div className="notice-box"><Package size={17}/><span>No repair option has been established. Continue the assessment or resolve the requested information/inspection.</span></div> }}
        {for option in a.options { <Card key={option.repair_id} className="detail-card repair-card"><CardHeader><div className="flex items-center gap-2"><Package size={17}/><CardTitle>{option.title}</CardTitle></div><CardDescription>Provisional · diagnosis must be confirmed</CardDescription></CardHeader><CardContent>
            <p>{option.explanation}</p>{for part in option.parts { <div key={part.sku}><strong>{part.sku}</strong><div className="part-stock"><span className={"stock-dot " + ("out" if part.quantity_available == 0 else "")}/><span>{str(part.quantity_available) + " available · " + money(part.unit_price_minor, part.currency)}</span></div></div> }}
            <dl className="cost-lines"><div><dt>Compatible parts</dt><dd>{money(option.estimate.parts_cost_minor, option.estimate.currency)}</dd></div><div><dt>Labour</dt><dd>{money(option.estimate.labour_cost_minor, option.estimate.currency)}</dd></div><div className="cost-total"><dt>Repair estimate before tax</dt><dd>{money(option.estimate.total_cost_minor, option.estimate.currency)}</dd></div></dl><p className="muted tiny">Catalogue snapshot. Customer payable is unresolved; stock is not reserved. Turnaround time has not been estimated.</p>
        </CardContent></Card> }}
        <div className="next-step"><span className="section-eyebrow">NEXT STEP</span><p>{a.next_action}</p></div>
    </div>;
}
