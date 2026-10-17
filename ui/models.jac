# Client view records. MongoDB records and specialist findings are authoritative.
cl obj:pub Message {
    has id: str = "";
    has role: str = "assistant";
    has text: str = "";
    has at: str = "";
    has internal: bool = False;
}

cl obj:pub Evidence {
    has id: str = "";
    has name: str = "";
    has kind: str = "photo";
    has mime: str = "";
    has size: int = 0;
    has preview: str = "";
}

cl obj:pub Decision {
    has id: str = "";
    has action: str = "";
    has reason: str = "";
    has origin: str = "owner";
    has scope: str = "Warranty repair proposal";
    has revision: int = 1;
    has at: str = "";
}

cl obj:pub CaseRecord {
    has id: str = "";
    has reference: str = "";
    has customer: str = "Alex Morgan";
    has customer_id: str = "alex";
    has title: str = "New laptop complaint";
    has description: str = "";
    has model: str = "Fixora Demo FD-100";
    has scenario: str = "complete";
    has status: str = "draft";
    has coverage: str = "needs_review";
    has stage: int = 0;
    has revision: int = 1;
    has version: int = 1;
    has assessed_revision: int = 0;
    has messages: list[Message] = [];
    has evidence: list[Evidence] = [];
    has decisions: list[Decision] = [];
    has inspection: str = "";
    has diagnosis: str = "";
    has correction: str = "";
    has clarified: bool = False;
    has retried: bool = False;
    has updated_at: str = "";
    has backend: any = None;
    has failure: str = "";
}

cl obj:pub Assessment {
    has purchase_date: str = "Not extracted";
    has expiry_date: str = "Not evaluated";
    has invoice: str = "Not extracted";
    has serial: str = "Not extracted";
    has seller: str = "Not extracted";
    has policy: str = "Not evaluated";
    has eligibility: str = "Date eligibility has not been established.";
    has coverage: str = "Not evaluated";
    has rationale: str = "Run the assessment to evaluate warranty coverage.";
    has observation: str = "No observations yet.";
    has limitation: str = "AI observations are provisional and do not confirm an internal fault.";
    has next_action: str = "Attach an invoice and product photos, then assess the complaint.";
    has mode: str = "Not assessed";
    has invoice_total: str = "Not extracted";
    has options: list[any] = [];
    has clauses: list[any] = [];
}
