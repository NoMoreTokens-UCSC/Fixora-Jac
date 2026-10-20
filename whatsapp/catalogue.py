"""Read-only shopping facts from the existing product and inventory collections.

The model selects IDs; only this code describes saved prices and stock. Missing
facts remain unknown. Parts share the repair agent's inventory source of truth.
"""
from decimal import Decimal
import re


class Catalogue:
    def __init__(self, store):
        self.store, self.db = store, store.db

    def entries(self):
        models = {p["_id"]: p for p in self.db.products.find({})}
        result = []
        for collection, category in (("products", "product"), ("inventory", "part")):
            for p in self.db[collection].find({"retail_enabled": {"$ne": False}}):
                if p.get("shop_id", self.store.settings.shop_id) != self.store.settings.shop_id:
                    continue
                compatibility = [models[mid]["model_code"] for mid in p.get("compatible_model_ids", []) if mid in models]
                qty, price, currency = p.get("quantity_available"), p.get("unit_price_minor"), p.get("currency")
                qty = qty if type(qty) is int and qty >= 0 else None
                price = price if type(price) is int and price >= 0 else None
                currency = currency if isinstance(currency, str) and re.fullmatch(r"[A-Z]{3}", currency) else None
                result.append({
                    "id": collection + ":" + str(p["_id"]),
                    "category": "accessory" if p.get("category") == "accessory" else category,
                    "name": p.get("display_name") or p.get("part_type", "Item").replace("_", " ").title(),
                    "code": p.get("model_code") or p.get("sku", ""),
                    "aliases": p.get("aliases", []), "compatible_models": compatibility,
                    "quantity_available": qty,
                    # Products use the same minor-unit convention as repair inventory.
                    "unit_price_minor": price, "currency": currency,
                    "synthetic": p.get("synthetic", False), "updated_at": p.get("updated_at", ""),
                })
        return result

    def answer(self, selected):
        ids = set(selected)
        # Reload facts after inference so a changed stock record is not quoted from
        # an earlier model prompt. Unknown IDs never become queries or prices.
        rows = [p for p in self.entries() if p["id"] in ids]
        if not rows:
            return ("Which product, spare part or accessory do you need? Please give its name and model or SKU. "
                    "I couldn't identify an exact catalogue match; the shop can confirm items not listed here.")
        lines = ["Catalogue matches:" if len(rows) > 1 else "Current catalogue information:"]
        if any(p["synthetic"] for p in rows):
            lines.append("DEMO DATA: these are fictional items, prices and stock, not a live shop offer.")
        for p in rows[:8]:
            qty, price, currency = p["quantity_available"], p["unit_price_minor"], p["currency"]
            stock = (f"In stock ({qty} available)" if qty > 0 else "Out of stock") if type(qty) is int and qty >= 0 else "Stock not confirmed"
            amount = (currency + " " + format(Decimal(price) / 100, ",.2f")) if (
                type(price) is int and price >= 0 and isinstance(currency, str) and re.fullmatch(r"[A-Z]{3}", currency)
            ) else "Price not confirmed"
            lines.append(f"{p['name']} [{p['code']}] — {stock}; {amount} per item.")
            if p["compatible_models"]:
                lines.append("Listed compatibility: " + ", ".join(p["compatible_models"]) + ". Confirm the exact variant with the shop.")
        if len(rows) > 1:
            lines.append("Which model or SKU do you mean? Please type the code if voice recognition got it wrong.")
        lines.append("Stock and prices are a saved snapshot and may change. This does not reserve stock; fitting/labour is separate. Ask the shop to confirm before purchase.")
        return "\n".join(lines)[:4000]
