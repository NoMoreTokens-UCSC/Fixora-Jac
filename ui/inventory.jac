import from .models { CaseRecord, PartAvailability, InventoryPart }

cl def:pub requirement_for(c: CaseRecord) -> str {
    return "Reported missing charger" if c.scenario in ["missing_charger", "uncertain_compatibility"] else "Replacement charging connector";
}

cl def:pub catalogue() -> list[InventoryPart] {
    return [
        InventoryPart(sku="FX-CH14", name="Studio 14 charging connector", models=["Studio 14"], stock=4, unit_minor=4500, labour_minor=2500),
        InventoryPart(sku="FX-CH15", name="Pro 15 charging connector", models=["Pro 15"], stock=2, unit_minor=5500, labour_minor=2500),
        InventoryPart(sku="FX-CH13", name="Air 13 charging connector", models=["Air 13"], stock=3, unit_minor=4000, labour_minor=2500),
        InventoryPart(sku="FX-AC14", name="Studio 14 charger", models=["Studio 14"], stock=5, unit_minor=6000),
        InventoryPart(sku="FX-AC15", name="Pro 15 charger", models=["Pro 15"], stock=2, unit_minor=7500),
        InventoryPart(sku="FX-AC13", name="Air 13 charger", models=["Air 13"], stock=3, unit_minor=5500)
    ];
}

async def:pub lookup_parts(c: CaseRecord, retry: bool = False) -> PartAvailability {
    result = PartAvailability(revision=c.revision, requirement=requirement_for(c), checked_at=new(Date).toISOString());
    result.attempts = c.availability.attempts + 1;
    result.provisional = c.scenario not in ["missing_charger", "replacement", "auto"] and c.diagnosis != "Charging connector failure confirmed";
    if c.scenario == "inventory_failure" and not retry and c.availability.attempts == 0 {
        result.status = "error";
        result.explanation = "The sample inventory service did not respond. Retry the stock check; your assessment and evidence are saved.";
        return result;
    }
    if c.model not in ["Studio 14", "Pro 15", "Air 13"] or (c.scenario == "uncertain_compatibility" and not c.clarified) or (c.scenario == "conflict" and not c.clarified) {
        result.status = "unknown";
        result.explanation = "Compatibility is not established. Confirm the model and matching charger/part specification in case details before reassessing. No part offer has been sent.";
        return result;
    }
    prefix = "FX-AC" if c.scenario in ["missing_charger", "uncertain_compatibility"] else "FX-CH";
    matches = [p for p in catalogue() if c.model in p.models and p.sku[:5] == prefix];
    if not matches {
        result.status = "unknown"; result.explanation = "No exact fictional catalogue match was found. Ask the shop to inspect the specification."; return result;
    }
    part = matches[0];
    result.sku = part.sku; result.part_name = part.name; result.unit_minor = part.unit_minor; result.labour_minor = part.labour_minor;
    result.compatibility = "confirmed";
    result.stock = 0 if c.scenario == "no_stock" else part.stock;
    result.status = "in_stock" if result.stock > 0 else "out_of_stock";
    result.explanation = "Matched against the fictional catalogue for " + c.model + ". This is a sample stock snapshot, not a live inventory query.";
    return result;
}
