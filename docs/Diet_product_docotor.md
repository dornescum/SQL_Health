# Diet ↔ Recommended Product ↔ Doctor Connections

How diets, recommended/prescribed products, and doctors connect across:

- `src/controllers/UserController.ts` — patient-facing consumption of the diet + prescription
- `src/controllers/OloproteicDietController.ts` — the doctor's V3 diet-compile/prescribe/send workflow (+ admin template CRUD)
- `src/controllers/ProductSectionController.ts` — admin taxonomy that buckets products into meal-time sections
- `src/controllers/ShopifyController.ts` — Shopify Admin API integration (customers, draft orders, catalog sync)
- `src/controllers/DoctorController.ts` — diagnostics/pattern-flagging engine; **not** where diets get assigned, despite the name

> **Read this first — the naming trap:** `DoctorController.ts` looks like the obvious place for "doctor assigns diet" logic, but it isn't. Its diet-related calls are all **read-only** (`DietAssignment.getByPatientUid`, `getByVisitId`, `isDietSentToPatient` — for displaying state on `patient-detail` / locking the T1 editor). The actual v2 "choose-diet → assign-diet" routes (`src/routes/doctor/index.ts:182-211`) are wired to a separate `DietController` (`src/controllers/DietController.ts`), not `DoctorController`. `DoctorController.getDietPage` is a dead-code stub with a hardcoded `example.com` medications list — no DB query, not part of the live flow. Treat `DietController` and `CartController` as the missing links in this picture; they weren't in the requested file set but the trail leads straight to them (noted where relevant below).

---

## 1. The actors, one paragraph each

**`ProductSectionController`** — pure admin config. Lets a super-doctor/admin assign each Shopify-linked product (`product_links`) to one or more meal-time sections (`MEAL_SECTIONS`: breakfast, lunch, dinner, accessories, cosmetics, …) via the `product_sections` table. No patient, diet, or doctor logic of its own — it only writes the taxonomy that `OloproteicDietController` later reads.

**`OloproteicDietController`** — the real hub. Two halves: (1) admin CRUD + translation + audit trail for `diet_oloproteic` templates, and (2) the doctor-facing workflow that turns a template into a prescribed, product-attached, emailed diet for one patient: pick a diet → compile dosage/fascia params → attach a supplement schedule (which products, which section, quantity) → preview the exact patient email → send it.

**`DoctorController`** — the diagnostics engine. `buildDiagnosticAggregates()` walks ~15 pathology domains (via `src/libs/calcul.ts` + `src/libs/utils/*Validation.ts`) and produces two free-text arrays: `diagNotes` (clinical flags) and `dietPresc` (plain-language diet/supplement advice like "drink 3L water daily", "ursodeoxycholic acid"). These get embedded as JSON in `diagnostic_notes_history.clinical_snapshot` and shown to the doctor on the diagnostics screen — but saving them never creates a `DietAssignment` or `DoctorPrescription` row. It's advisory text the doctor reads before going to `OloproteicDietController` to actually assign something.

**`ShopifyController`** — the Shopify Admin API layer. Customer sync, draft-order/checkout creation, product catalog sync (`shopify_products`), plus admin reporting/product-prescribable-toggle screens. It has **no concept of a diet** — it only knows about cart line items (`shopify_variant_id` + quantity) and an opaque `oloproteicMeta: { cartId, prescriptionId, doctorId }` passed in by whatever caller built the cart (that caller is `CartController`, out of scope here but the actual glue between `doctor_prescriptions` and Shopify).

**`UserController`** — the patient's view of the finished product. `getClientMedicalData`, `getMyVisits`, `getMyVisitDetail`, `getMyV3Diet` all fetch `DietAssignment` plus `DoctorPrescription.getByDietAssignmentId()` / `DoctorPrescription.parseSchedule()` to render the patient's assigned diet alongside their prescribed supplement schedule and its purchase status.

---

## 2. Tables touched, by controller

| Table | ProductSectionController | OloproteicDietController | DoctorController | ShopifyController | UserController |
|---|---|---|---|---|---|
| `product_sections` | write (`setProductSections`) | read (`ProductSection.getSectionMap()`) | — | read (raw SQL join, `runProductSync`) | — |
| `product_section_audit_log` | write | — | — | — | — |
| `product_links` | read (raw SQL) | read (`ProductLinkModel.getPrescribable/getAll`) | — | read/write (`ProductLinkModel`, `assignProductLink`, `setPrescribable`) | — |
| `shopify_products` | read (joined) | read (joined via `ProductLinkModel`) | — | read/write (`ShopifyProduct` model, catalog sync) | — |
| `diet_oloproteic` / `diet_oloproteic_sections` | — | read/write (`DietOloproteicModel`/`DietOloproteicSectionModel`) | — | — | — |
| `diet_oloproteic_audit_log` | — | write (`DietAuditLog`) | — | — | — |
| `patient_diet_assignments` | — | write (`DietAssignment.assignV3()` in `saveCompile`), read elsewhere | read-only (`getByPatientUid`, `getByVisitId`, `isDietSentToPatient`) | — | read (`DietAssignment.getByPatientUid`, `getLatestV3ByPatientUid`, `getV3AssignmentById`) |
| `doctor_prescriptions` | — | write (`DietPrescription.upsert()` in `savePrescription`) | — | consumed only as an opaque `prescriptionId` string in draft-order metadata | read (`DoctorPrescription.getByDietAssignmentId(s)`, `.parseSchedule()`) |
| `diagnostic_notes_history` | — | read (`Doctor.getPatientMedicalData`, shared model) | read/write (`buildDiagnosticAggregates` output → `clinical_snapshot`) | — | read (`DiagnosticNotesHistory.getAllByClient`, for standalone-diet diagnostics) |

---

## 3. The actual flow, in order

```
1. ProductSectionController:      admin assigns Shopify products → meal-time sections   (product_sections)
                                                     │
2. DoctorController:              buildDiagnosticAggregates() → diagNotes + dietPresc   (diagnostic_notes_history.clinical_snapshot)
   (advisory text only — no writes to diet/prescription tables)
                                                     │  doctor reads this, then goes to:
3. OloproteicDietController.showSelection:           surfaces the same diagNotes on the diet-picker screen
                                                     │
4. OloproteicDietController.showCompile → saveCompile:
       DietAssignment.assignV3()  →  patient_diet_assignments  (the actual "diet assigned" row)
                                                     │
5. OloproteicDietController.savePrescription:
       DietPrescription.upsert() →  doctor_prescriptions
       (uses ProductLinkModel.getPrescribable() + ProductSection.getSectionMap() from step 1
        to know which products belong in which meal-time section)
                                                     │
6. OloproteicDietController.showDietEmailPreview / sendDietToPatient:
       builds the patient email HTML — diet sections + per-section supplement list +
       a "Prodotti da Acquistare" (products to buy) box-count summary
                                                     │
   [out of scope, but this is where it goes next] CartController turns doctor_prescriptions
   into a Shopify cart and calls:
                                                     │
7. ShopifyController.createShopifyDraftOrder:
       cart.items (shopify_variant_id + qty) → Shopify draftOrderCreate
       customAttributes: oloproteic_cart_id / oloproteic_prescription_id / oloproteic_doctor_id
       → returns invoiceUrl (Shopify-hosted checkout link) the patient pays
                                                     │
8. UserController.getMyVisits / getMyV3Diet / getClientMedicalData:
       DietAssignment + DoctorPrescription.getByDietAssignmentId().parseSchedule()
       → patient sees their diet, its supplement schedule, and purchase status
```

The link from step 6/7 back to "purchased" state (marking a `doctor_prescriptions.status` as `purchased` after Shopify payment) is handled by the Shopify **webhook** handler (`src/routes/shopify/webhook.ts`), not by any of the five requested controllers — `ShopifyController` only *reads* that webhook's event log (`getWebhookEventLog()`) for the admin activity feed, it doesn't process the webhook itself.

---

## 4. Notes worth flagging

- **Typo'd table in `OloproteicDietController.saveCompile()`** (line ~895): a fire-and-forget logging query selects from `diets_oloproteic` (plural) — no such table exists in the migrations (only singular `diet_oloproteic`). It's wrapped in `.catch(() => {})` so it fails silently and falls back to default values; cosmetic (logging only), but worth a one-line fix.
- **`DoctorController.getDietPage` is dead code** (line 737, routed separately in `src/routes/doctor/index.ts:41`): renders `doctor/diet` with a hardcoded `medications` array pointing at `example.com`. Not called by the real prescribing flow — safe to delete or worth a `// dead code` comment so it isn't mistaken for the live path.
- **Shopify integration is diet-agnostic by design**: `ShopifyController` never queries a diet table; it only ever sees `doctorId`/`prescriptionId`/`cartId` as opaque strings passed through custom attributes. All the "is this product part of a diet" logic lives upstream in `OloproteicDietController` + `ProductSectionController` before a cart is ever built.
