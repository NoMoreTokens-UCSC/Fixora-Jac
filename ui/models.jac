# Client-only records. The asynchronous gateway owns persistence and transitions.
cl obj:pub Message {
    has id: str = "";
    has role: str = "assistant";
    has text: str = "";
    has at: str = "";
    has internal: bool = False;
    has kind: str = "";
    has revision: int = 0;
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
    has requirement: str = "Replacement charging connector";
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
    has model: str = "Studio 14";
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
    has availability: PartAvailability = PartAvailability();
}

cl obj:pub Assessment {
    has purchase_date: str = "2026-03-12";
    has expiry_date: str = "2027-03-12";
    has invoice: str = "INV-DEMO-1048";
    has serial: str = "FX-DEMO-0142";
    has seller: str = "Fixora laptop shop (fictional)";
    has policy: str = "Demo shop policy v1 · W-01 / R-02";
    has eligibility: str = "Within the sample 12-month period";
    has coverage: str = "Potentially covered";
    has rationale: str = "The sample purchase is within the warranty period. An owner must confirm the supported repair condition.";
    has observation: str = "The sample product label identifies the model. The complaint reports intermittent charging; these images cannot establish an internal electrical fault.";
    has limitation: str = "Fixture findings only. Your uploaded images are previews and have not been analysed by AI.";
    has repair: str = "Charging connector inspection / replacement";
    has part: str = "FX-CH14 · Studio 14 charging connector";
    has stock: int = 4;
    has part_minor: int = 4500;
    has labour_minor: int = 2500;
    has next_action: str = "The shop will review the evidence and proposal.";
}
