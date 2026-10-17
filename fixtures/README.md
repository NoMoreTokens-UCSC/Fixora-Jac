# Shared fixtures — Member B

The four catalogue files now contain one fictional shop policy, three fictional laptop models, three repair definitions and nine stock records. All IDs use the `demo-` prefix. Run `jac run data/seed.jac` explicitly to load them; repeated runs replace records with the same IDs. Prices are illustrative LKR minor units, not market prices.

| File | Intended content |
| --- | --- |
| `policies.json` | One fictional shop policy with versioned clause IDs and date rules |
| `products.json` | Three explicitly supported laptop models |
| `repairs.json` | Supported diagnosis/repair categories and labour values |
| `inventory.json` | Compatible SKUs, seeded quantities, prices and known lead times |

Use stable IDs; store money in integer minor units with currency. Member A implements the idempotent database loader in `data/seed.jac`.

Prepare shared input/result fixtures for:

1. Complete evidence producing an evidence-backed recommendation.
2. Invoice/product mismatch requiring clarification.
3. Visible damage plus an uncertain fault requiring inspection.

`scenarios.json` specifies exact inputs/descriptions and expected outcomes. The five PNGs in `evidence/` are labelled synthetic illustrations/invoices. `demo_evidence.json` maps SHA-256 hashes of their bytes to recorded extraction outputs. With `FIXORA_DEMO_MODE=true`, only these exact image bytes are accepted and all results are labelled `demo_fixture`. This is explicit fixture replay, not a live model call. Disable that setting to analyze arbitrary images through the configured model.

See [MEMBER_B_HANDOFF.md](../MEMBER_B_HANDOFF.md) for provider setup, scenario details and the fields Member C should render. Do not add real customer data or secrets.
