# Client-only records. The asynchronous gateway owns persistence and transitions.
cl obj:pub Message {
    has id: str = "";
    has role: str = "assistant";
    has text: str = "";
    has at: str = "";
    has internal: bool = False;
    has kind: str = "";
    has revision: int = 0;
    has delivery: str = "";
}

cl obj:pub InventoryPart {
    has sku: str = "";
    has name: str = "";
    has models: list[str] = [];
    has stock: int = 0;
    has unit_minor: int = 0;
    has labour_minor: int = 0;
}

cl obj:pub PartAvailability {
    has revision: int = 0;
    has requirement: str = "No saved repair option";
    has sku: str = "";
    has part_name: str = "";
    has compatibility: str = "unknown";
    has status: str = "unchecked";
    has stock: int = 0;
    has unit_minor: int = 0;
    has labour_minor: int = 0;
    has provisional: bool = True;
    has checked_at: str = "";
    has explanation: str = "";
    has message_id: str = "";
    has publication_key: str = "";
    has attempts: int = 0;
    has currency: str = "";
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
    has customer: str = "";
    has customer_id: str = "";
    has title: str = "New laptop complaint";
    has description: str = "";
    has model: str = "Unconfirmed";
    has scenario: str = "live";
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
    has availability: PartAvailability = PartAvailability();
    has findings: Assessment = Assessment();
    has analysis_mode: str = "No assessment yet";
    has assessment_status: str = "draft";
    has review_status: str = "unreviewed";
}

cl obj:pub Assessment {
    has purchase_date: str = "Unknown";
    has expiry_date: str = "Unknown";
    has invoice: str = "Unknown";
    has serial: str = "Unknown";
    has seller: str = "Unknown";
    has policy: str = "Not evaluated";
    has eligibility: str = "Not evaluated";
    has coverage: str = "Not evaluated";
    has rationale: str = "No assessment for the current inputs.";
    has observation: str = "No saved observations.";
    has limitation: str = "A diagnosis has not been confirmed.";
    has repair: str = "No repair proposal";
    has part: str = "";
    has stock: int = 0;
    has part_minor: int = 0;
    has labour_minor: int = 0;
    has next_action: str = "Await customer evidence.";
    has invoice_total: str = "Unknown";
    has currency: str = "";
}
