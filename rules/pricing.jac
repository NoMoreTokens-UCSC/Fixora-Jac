import from shared.contracts { FixoraError }

def _estimate(repair: dict[str, any], parts: list[dict[str, any]]) -> dict[str, any] {
    currency = repair.get("currency");
    labour = repair.get("labour_cost_minor");
    if not isinstance(currency, str) or len(currency) != 3 or type(labour) is not int or labour < 0 {
        raise FixoraError("INVALID_CATALOGUE", "Repair labour and currency are invalid.");
    }
    if `any(part.get("currency") != currency for part in parts) {
        raise FixoraError("INVALID_CATALOGUE", "Cannot combine prices in different currencies.");
    }
    for part in parts {
        if type(part.get("unit_price_minor")) is not int or part["unit_price_minor"] < 0 {
            raise FixoraError("INVALID_CATALOGUE", "Part price must be nonnegative integer minor units.");
        }
    }
    parts_total = sum(part["unit_price_minor"] as int for part in parts);
    return {"currency": currency, "parts_cost_minor": parts_total, "labour_cost_minor": labour,
        "total_cost_minor": parts_total + (labour as int), "provisional": True,
        "customer_payable_minor": None, "tax_included": False,
        "explanation": "Illustrative repair estimate before tax; final diagnosis, coverage and charges are not established."};
}
