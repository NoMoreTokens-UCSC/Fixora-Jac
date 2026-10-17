# Shared fixtures — Member B

The four JSON files currently contain empty arrays. They are placeholders, not usable seed data. Finalize record shapes with Member A before populating them.

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

Save the scenario files here after agreeing the contracts. Use synthetic invoices and photos you can share with the team. Keep files small and label any saved model output as a fixture. Do not add real customer data or secrets.
