import calendar;
import from datetime { date }
import from shared.contracts { FixoraError }

def _iso_date(value: any) -> date | None {
    if not isinstance(value, str) or len(value) != 10 { return None; }
    try {
        parsed = date.fromisoformat(value);
        return parsed if parsed.isoformat() == value else None;
    } except ValueError { return None; }
}

def _coverage(invoice: dict[str, any], policy: dict[str, any] | None,
    observations: list[dict[str, any]], evaluation_date: str) -> dict[str, any] {
    purchased = _iso_date(invoice.get("purchase_date"));
    today = _iso_date(evaluation_date);
    if purchased is None or today is None or purchased > today {
        return {"outcome": "needs_information", "date_eligible": None, "explanation": "A valid purchase date on or before the evaluation date is required."};
    }
    if policy is None or policy.get("expiry_rule") != "calendar_months_inclusive_clamped" {
        return {"outcome": "needs_inspection", "date_eligible": None, "explanation": "No supported, versioned shop policy is available."};
    }
    active_policy = policy as dict[str, any];
    months = active_policy.get("duration_months");
    if type(months) is not int or months < 1 or months > 120 {
        raise FixoraError("INVALID_CATALOGUE", "Policy duration must be between 1 and 120 calendar months.");
    }
    month_index = purchased.year * 12 + purchased.month - 1 + (months as int);
    year = month_index // 12;
    month = month_index % 12 + 1;
    expiry = date(year, month, min(purchased.day, calendar.monthrange(year, month)[1]));
    clauses = active_policy.get("clauses", []) as list[dict[str, any]];
    clause_ids = [row["id"] for row in clauses if row.get("kind") == "period"];
    result: dict[str, any] = {"policy_id": active_policy["_id"], "policy_version": active_policy["version"],
        "purchase_date": purchased.isoformat(), "evaluation_date": today.isoformat(),
        "expiry_date": expiry.isoformat(), "date_eligible": today <= expiry, "clause_ids": clause_ids,
        "outcome": "outside_period" if today > expiry else "potentially_covered",
        "explanation": "Warranty period has expired." if today > expiry else "Within the warranty period; coverage is conditional on the fault and policy exclusions."};
    if today > expiry { return result; }
    categories = set(row["category"] for row in observations);
    affected: list[str] = [];
    for clause in clauses {
        if clause.get("kind") == "visible_damage_exclusion" {
            matches = [category for category in clause.get("categories", []) if category in categories];
            if matches { clause_ids.append(clause["id"]); affected.extend(matches); }
        }
    }
    result["excluded_visible_categories"] = sorted(set(affected));
    if affected {
        result["outcome"] = "visible_damage_excluded";
        result["explanation"] = "The listed visible physical damage is excluded for the affected component. This does not establish the cause or coverage of other faults.";
    }
    return result;
}
