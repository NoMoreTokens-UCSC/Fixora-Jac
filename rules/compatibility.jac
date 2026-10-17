import from shared.contracts { FixoraError }

def _normalize(value: any) -> str { return str(value or "").strip().casefold(); }

def _resolve_model(manufacturer: any, model_code: any, products: list[dict[str, any]]) -> str | None {
    if not model_code { return None; }
    matches = [row["_id"] for row in products if _normalize(row["model_code"]) == _normalize(model_code)
        and (not manufacturer or _normalize(row["manufacturer"]) == _normalize(manufacturer))];
    return matches[0] if len(matches) == 1 else None;
}

def _choose_part(model_id: str, part_type: str, inventory: list[dict[str, any]], currency: str) -> dict[str, any] | None {
    candidates: list[dict[str, any]] = [];
    for row in inventory {
        if model_id not in row.get("compatible_model_ids", []) or row.get("part_type") != part_type { continue; }
        if row.get("currency") != currency { continue; }
        if type(row.get("unit_price_minor")) is not int or row["unit_price_minor"] < 0
            or type(row.get("quantity_available")) is not int or row["quantity_available"] < 0 or not row.get("sku") {
            raise FixoraError("INVALID_CATALOGUE", "Compatible inventory has invalid price, stock, or SKU.");
        }
        candidates.append(row);
    }
    candidates.sort(key=_part_rank);
    return candidates[0] if candidates else None;
}

def _part_rank(row: dict[str, any]) -> tuple[bool, int, str] {
    return (row["quantity_available"] <= 0, row["unit_price_minor"] as int, row["sku"] as str);
}
