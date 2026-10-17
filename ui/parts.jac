import from "lucide-react" { Package, RefreshCw, ArrowRight, AlertCircle, CircleHelp }
import from ..components.ui.button { Button }
import from .models { CaseRecord }
import from .inventory { requirement_for }

cl def part_money(value: int) -> str { return f"USD {value / 100:.2f}"; }

def:pub PartsAvailability(c: CaseRecord, compact: bool, busy: bool, onAction: Callable[[str], None]) -> JsxElement {
    a = c.availability;
    current = a.revision == c.revision and a.status != "unchecked";
    stale = a.revision > 0 and a.revision != c.revision;
    title = "Sample stock not checked yet";
    if stale { title = "A fresh part check is needed"; }
    elif current {
        title = "Available from our shop" if a.status == "in_stock" else ("Currently out of stock" if a.status == "out_of_stock" else ("Stock check interrupted" if a.status == "error" else "Let's confirm compatibility"));
    }
    return <section className="parts-availability" aria-label="Part and availability">
        <div className="parts-heading"><Package size={24}/><div><h3>Part & availability</h3><p>Sample catalogue · no live inventory connection</p></div></div>
        <div className="part-status" role="status"><span className={"stock-dot " + ("out" if current and a.status != "in_stock" else "")}/><strong>{title}</strong></div>
        <p>{requirement_for(c)}</p>
        {if current { <div className="current-part">
            {if a.compatibility == "confirmed" {
                <h4>{a.part_name}</h4><dl className="part-facts"><div><dt>Part reference</dt><dd>{a.sku}</dd></div><div><dt>Compatibility</dt><dd>{"Fictional catalogue match · " + c.model}</dd></div><div><dt>Sample stock</dt><dd>{str(a.stock) + " available" if a.stock > 0 else "0 · arrival unknown"}</dd></div><div><dt>Sample unit price</dt><dd>{part_money(a.unit_minor)}</dd></div>{if a.labour_minor > 0 { <div><dt>Sample labour</dt><dd>{part_money(a.labour_minor)}</dd></div><div><dt>Sample repair total</dt><dd>{part_money(a.unit_minor + a.labour_minor)}</dd></div> }}</dl>
            }}
            <p className="part-explanation">{a.explanation}</p>
            {if a.provisional and a.compatibility == "confirmed" { <div className="part-caution"><CircleHelp size={18}/><p>Candidate replacement only. The shop must confirm the fault and final fit before any repair.</p></div> }}
            <p className="part-check-time">{"Checked for revision " + str(a.revision) + " · " + a.checked_at[:10] + " " + a.checked_at[11:16] + " UTC"}</p>
        </div> } else { <p className="part-explanation">{"The case details changed. Earlier availability is historical; reassess this revision before relying on it." if stale else "The demo matches your confirmed details against a fictional parts catalogue during assessment. No uploaded image is analysed."}</p> }}
        <div className="part-actions">
            {if compact and current and a.status == "in_stock" and a.compatibility == "confirmed" { <Button variant="default" disabled={busy} onClick={lambda { onAction("ask_part"); }}>Ask the shop about this part<ArrowRight size={17}/></Button> }}
            <Button variant="outline" disabled={busy or c.stage < 4 or c.status in ["draft", "needs_information", "needs_inspection", "failed"]} onClick={lambda { onAction("retry_parts" if current and a.status == "error" else "check_parts"); }}><RefreshCw size={16} className={"spin" if busy else ""}/>{"Checking…" if busy else ("Retry stock check" if current and a.status == "error" else ("Refresh sample stock" if current else "Check sample stock"))}</Button>
            {if current and a.status == "unknown" { <Button variant="outline" disabled={busy} onClick={lambda { onAction("correct"); }}>Confirm part details</Button> }}
        </div>
        <p className="part-boundary">Sample prices are not a firm quote. Availability does not establish warranty coverage, approve a repair, make a purchase, or reserve stock.</p>
    </section>;
}
