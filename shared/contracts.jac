# Owner: Member A. Shared wire and specialist contracts; no database handles.

sv obj ErrorInfo {
    has code: str;
    has message: str;
}

sv obj ApiResult {
    has ok: bool;
    has data: dict[str, any] = {};
    has error: ErrorInfo | None = None;
}

sv obj FixoraError(Exception) {
    has code: str;
    has message: str;

    def postinit {
        Exception.__init__(self, self.message);
    }
}

obj InvoiceFields {
    has invoice_number: str | None = None;
    has purchase_date: str | None = None;
    has model_id: str | None = None;
    has serial_number: str | None = None;
    has seller: str | None = None;
    has amount_minor: int | None = None;
    has currency: str | None = None;
    has source_text: str = "";
    has evidence_refs: list[str] = [];
}

obj Observation {
    has description: str;
    has evidence_refs: list[str];
    has limitations: list[str] = [];
    has provisional: bool = True;
}

obj CoverageResult {
    has outcome: str = "needs_review";
    has date_eligible: bool | None = None;
    has policy_id: str | None = None;
    has policy_version: int | None = None;
    has clause_ids: list[str] = [];
    has explanation: str = "";
}

obj PartSnapshot {
    has sku: str;
    has model_id: str;
    has quantity_available: int;
    has unit_price_minor: int;
    has currency: str;
}

obj RepairOption {
    has repair_id: str;
    has explanation: str;
    has evidence_refs: list[str] = [];
    has parts: list[PartSnapshot] = [];
    has provisional: bool = True;
}

sv obj StageResult {
    has stage: str;
    has status: str;
    has findings: dict[str, any] = {};
    has evidence_refs: list[str] = [];
    has missing_fields: list[str] = [];
    has conflicts: list[str] = [];
    has next_action: str = "continue";
    has error: ErrorInfo | None = None;
}

def _success(data: dict[str, any]) -> ApiResult {
    return ApiResult(ok=True, data=data);
}

def _failure(code: str, message: str) -> ApiResult {
    return ApiResult(ok=False, error=ErrorInfo(code=code, message=message));
}
