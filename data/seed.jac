# Owner: Member A. Explicit opt-in loader; never runs on server import/startup.
import json;
import sys;
import from pathlib { Path }
import from data.connection { _get_database, _close_connection }
import from shared.config { _get_settings }
import from shared.contracts { FixoraError }

def _seed_catalogue(fixture_directory: str = "fixtures") -> dict[str, int] {
    mapping = {"policies": "policies", "products": "products",
        "repairs": "repair_catalog", "inventory": "inventory"};
    loaded: dict[str, list[dict[str, any]]] = {};
    for filename in mapping {
        raw = json.loads((Path.cwd() / fixture_directory / (filename + ".json")).read_text(encoding="utf-8"));
        if not isinstance(raw, list) {
            raise FixoraError("VALIDATION_ERROR", "Each catalogue fixture must contain a JSON array.");
        }
        records: list[dict[str, any]] = [];
        seen: set[str] = set();
        for row in raw {
            if not isinstance(row, dict) or not isinstance(row.get("_id"), str) or not row["_id"] {
                raise FixoraError("VALIDATION_ERROR", "Every seed record needs a nonempty string _id.");
            }
            if row["_id"] in seen { raise FixoraError("VALIDATION_ERROR", "Seed record IDs must be unique within each file."); }
            seen.add(row["_id"]);
            if filename == "policies" { row["shop_id"] = _get_settings().shop_id; }
            records.append(row);
        }
        loaded[filename] = records;
    }
    if not `any(loaded.values()) {
        raise FixoraError("EMPTY_FIXTURES", "Member B must populate the catalogue fixtures before seeding.");
    }
    _validate_seed_records(loaded);
    counts: dict[str, int] = {};
    database = _get_database();
    for filename in mapping {
        counts[filename] = 0;
        for row in loaded[filename] {
            database[mapping[filename]].replace_one({"_id": row["_id"]}, row, upsert=True);
            counts[filename] += 1;
        }
    }
    return counts;
}

def _validate_seed_records(loaded: dict[str, list[dict[str, any]]]) {
    if not all(loaded.values()) {
        raise FixoraError("VALIDATION_ERROR", "Populate all four catalogue files before seeding.");
    }
    model_ids = set(row["_id"] for row in loaded["products"]);
    for row in loaded["products"] {
        if not row.get("manufacturer") or not row.get("model_code") or not row.get("display_name") {
            raise FixoraError("VALIDATION_ERROR", "Products need manufacturer, model_code and display_name.");
        }
    }
    for row in loaded["policies"] {
        if type(row.get("version")) is not int or row["version"] < 1 or type(row.get("duration_months")) is not int or row["duration_months"] < 1 {
            raise FixoraError("VALIDATION_ERROR", "Policies need positive integer version and duration_months.");
        }
        if not isinstance(row.get("clauses"), list) or not row["clauses"] or not row.get("expiry_rule") {
            raise FixoraError("VALIDATION_ERROR", "Policies need nonempty clauses and an explicit expiry_rule.");
        }
    }
    for collection_name in ["repairs", "inventory"] {
        for row in loaded[collection_name] {
            compatible = row.get("compatible_model_ids");
            if not isinstance(compatible, list) or not compatible or not all(model_id in model_ids for model_id in compatible) {
                raise FixoraError("VALIDATION_ERROR", "Repair and inventory compatibility must reference supported product IDs.");
            }
            amount_key = "labour_cost_minor" if collection_name == "repairs" else "unit_price_minor";
            if type(row.get(amount_key)) is not int or row[amount_key] < 0 {
                raise FixoraError("VALIDATION_ERROR", "Catalogue prices must be nonnegative integer minor units.");
            }
            if collection_name == "inventory" {
                if not row.get("sku") or not row.get("part_type") or type(row.get("quantity_available")) is not int or row["quantity_available"] < 0 {
                    raise FixoraError("VALIDATION_ERROR", "Inventory needs SKU, part_type and a nonnegative integer quantity.");
                }
                currency = row.get("currency");
                if not isinstance(currency, str) or len(currency) != 3 or not currency.isupper() {
                    raise FixoraError("VALIDATION_ERROR", "Inventory needs a three-letter uppercase currency code.");
                }
            } elif not row.get("diagnosis_code") or not isinstance(row.get("required_part_types"), list) {
                raise FixoraError("VALIDATION_ERROR", "Repairs need diagnosis_code and required_part_types.");
            }
        }
    }
    skus = [row["sku"] for row in loaded["inventory"]];
    if len(skus) != len(set(skus)) { raise FixoraError("VALIDATION_ERROR", "Seed inventory SKUs must be unique."); }
}

with entry:__main__ {
    try { print(_seed_catalogue()); }
    except FixoraError as error { print(error.code + ": " + error.message); sys.exit(1); }
    except Exception { print("SEED_FAILED: Check fixture structure and server-side database configuration."); sys.exit(1); }
    finally { _close_connection(); }
}
