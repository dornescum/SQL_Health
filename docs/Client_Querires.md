# SQL Portfolio — Client-Focused Queries

Companion reference for the SQL portfolio project (`sql-project`, separate repo)
described in that project's `docs/project.md`. This file collects MySQL queries
built against **this app's actual schema**, scoped to the "client" domain only,
derived from:

- `src/controllers/UserController.ts` — client medical data, visit/diet history
- `src/controllers/PrimaVisitaController.ts` — first-visit ("Prima Visita") intake
  funnel across ~20 sections
- `src/controllers/PaymentController.ts` — visit payments, eligibility rules

Each query is written to be copy-pasteable into the portfolio's `sql/ctes/`,
`sql/views/`, or `sql/transactions/` files, or run directly against an anonymized
clone. They intentionally showcase CTEs, window functions, a transaction, and a
view — the four skills `project.md` wants headlined.

> **Schema note:** column names/types below are taken directly from
> `src/db/structure.sql` and the migration files in `src/db/migrations/files/`,
> not guessed. `visits.visit_type = '1'` is the first visit, `'2'` is the
> 30-day checkup. Clients are `users` rows with `role_id = 6` (the column
> default).

---

## 1. User / Client Profile

### 1.1 Active clients by country and town

```sql
SELECT country, town, COUNT(*) AS active_clients
FROM users
WHERE role_id = 6
  AND is_active = 1
  AND soft_delete = 0
GROUP BY country, town
ORDER BY active_clients DESC;
```

### 1.2 Client signups per month with running total (CTE + window function)

```sql
WITH monthly_signups AS (
  SELECT
    DATE_FORMAT(created_at, '%Y-%m-01') AS signup_month,
    COUNT(*) AS new_clients
  FROM users
  WHERE role_id = 6
  GROUP BY signup_month
)
SELECT
  signup_month,
  new_clients,
  SUM(new_clients) OVER (ORDER BY signup_month) AS cumulative_clients,
  ROUND(
    100 * (new_clients - LAG(new_clients) OVER (ORDER BY signup_month))
    / NULLIF(LAG(new_clients) OVER (ORDER BY signup_month), 0),
    1
  ) AS mom_growth_pct
FROM monthly_signups
ORDER BY signup_month;
```

### 1.3 Blocked client audit (self-join on `blocked_by`)

```sql
SELECT
  blocked.id AS client_id,
  blocked.name,
  blocked.surname,
  blocked.email,
  blocked.blocked_reason,
  blocked.blocked_at,
  admin.name AS blocked_by_admin
FROM users blocked
LEFT JOIN users admin ON admin.id = blocked.blocked_by
WHERE blocked.role_id = 6
  AND blocked.blocked_at IS NOT NULL
ORDER BY blocked.blocked_at DESC;
```

### 1.4 Client activity recency ranking (CTE + `RANK()`)

Most recent visit or payment activity per client, ranked oldest-to-return-to
first — useful for a re-engagement report.

```sql
WITH last_activity AS (
  SELECT
    u.id AS client_id,
    u.name,
    u.surname,
    GREATEST(
      COALESCE(MAX(v.created_at), '1970-01-01'),
      COALESCE(MAX(p.payment_date), '1970-01-01')
    ) AS last_seen_at
  FROM users u
  LEFT JOIN visits v ON v.client_id = u.id
  LEFT JOIN client_payments p ON p.user_id = u.id AND p.visit_paid = 1
  WHERE u.role_id = 6
  GROUP BY u.id, u.name, u.surname
)
SELECT
  client_id, name, surname, last_seen_at,
  DATEDIFF(CURRENT_DATE, last_seen_at) AS days_since_last_seen,
  RANK() OVER (ORDER BY last_seen_at ASC) AS inactivity_rank
FROM last_activity
ORDER BY last_seen_at ASC
LIMIT 50;
```

---

## 2. Payments & Revenue

### 2.1 Monthly revenue by visit type, with month-over-month change (CTE + `LAG`)

```sql
WITH monthly_revenue AS (
  SELECT
    DATE_FORMAT(payment_date, '%Y-%m-01') AS revenue_month,
    visit_type,                              -- '1' = first visit, '2' = checkup
    SUM(amount) AS total_revenue,
    COUNT(*) AS paid_visits
  FROM client_payments
  WHERE payment_status = 'completed'
    AND visit_paid = 1
  GROUP BY revenue_month, visit_type
)
SELECT
  revenue_month,
  visit_type,
  paid_visits,
  total_revenue,
  total_revenue - LAG(total_revenue) OVER (
    PARTITION BY visit_type ORDER BY revenue_month
  ) AS revenue_change_vs_prev_month
FROM monthly_revenue
ORDER BY revenue_month, visit_type;
```

### 2.2 Payment status funnel with share of total (CTE + window `SUM() OVER()`)

```sql
WITH status_counts AS (
  SELECT payment_status, COUNT(*) AS n, SUM(amount) AS gross_amount
  FROM client_payments
  GROUP BY payment_status
)
SELECT
  payment_status,
  n,
  gross_amount,
  ROUND(100 * n / SUM(n) OVER (), 1) AS pct_of_all_payments
FROM status_counts
ORDER BY n DESC;
```

### 2.3 First-visit yearly re-eligibility (mirrors `checkFirstVisitYearlyEligibility`)

One row per client with their most recent **completed first-visit** payment,
days remaining until they may pay for another first visit (365-day rule).

```sql
WITH last_first_visit AS (
  SELECT
    user_id,
    MAX(payment_date) AS last_first_visit_paid_at
  FROM client_payments
  WHERE visit_type = '1'
    AND visit_paid = 1
    AND payment_status = 'completed'
  GROUP BY user_id
)
SELECT
  u.id AS client_id,
  u.name,
  u.surname,
  l.last_first_visit_paid_at,
  DATEDIFF(CURRENT_DATE, l.last_first_visit_paid_at) AS days_since_first_visit,
  GREATEST(365 - DATEDIFF(CURRENT_DATE, l.last_first_visit_paid_at), 0) AS days_until_eligible,
  DATEDIFF(CURRENT_DATE, l.last_first_visit_paid_at) >= 365 AS can_pay_first_visit
FROM users u
JOIN last_first_visit l ON l.user_id = u.id
WHERE u.role_id = 6
ORDER BY days_until_eligible DESC;
```

### 2.4 Checkup (30-day) eligibility (mirrors `checkVisitEligibility` / `VISIT_INTERVALS.FIRST_TO_CHECKUP`)

Clients who completed and paid a first visit, have **not yet** paid a checkup,
and are past the 30-day waiting window.

```sql
WITH first_visits AS (
  SELECT user_id, visit_id, payment_date AS first_visit_paid_at
  FROM client_payments
  WHERE visit_type = '1' AND visit_paid = 1 AND payment_status = 'completed'
),
checkup_visits AS (
  SELECT DISTINCT user_id
  FROM client_payments
  WHERE visit_type = '2' AND visit_paid = 1 AND payment_status = 'completed'
)
SELECT
  u.id AS client_id,
  u.name,
  u.surname,
  fv.first_visit_paid_at,
  DATEDIFF(CURRENT_DATE, fv.first_visit_paid_at) AS days_since_first_visit
FROM users u
JOIN first_visits fv ON fv.user_id = u.id
LEFT JOIN checkup_visits cv ON cv.user_id = u.id
WHERE cv.user_id IS NULL
  AND DATEDIFF(CURRENT_DATE, fv.first_visit_paid_at) >= 30
ORDER BY days_since_first_visit DESC;
```

### 2.5 Top-paying clients (window function `RANK()`)

```sql
SELECT
  u.id AS client_id,
  u.name,
  u.surname,
  SUM(p.amount) AS total_paid,
  COUNT(*) AS visits_paid,
  RANK() OVER (ORDER BY SUM(p.amount) DESC) AS spend_rank
FROM users u
JOIN client_payments p ON p.user_id = u.id
WHERE p.payment_status = 'completed' AND p.visit_paid = 1
GROUP BY u.id, u.name, u.surname
ORDER BY spend_rank
LIMIT 20;
```

### 2.6 Transaction demo — confirm payment and lock the visit atomically

Mirrors `PaymentController.recordPayment`: mark the payment `completed`, lock
the associated visit, and pull the confirmation row back out — all inside one
transaction so a failure rolls back both writes together.

```sql
START TRANSACTION;

UPDATE client_payments
SET visit_paid = 1,
    payment_status = 'completed',
    payment_date = NOW(),
    payment_method = 'card'
WHERE payment_intent_id = :stripe_payment_intent_id;

UPDATE visits v
JOIN client_payments p ON p.visit_id = v.visit_id
SET v.visit_is_locked = 1
WHERE p.payment_intent_id = :stripe_payment_intent_id
  AND p.visit_type = '1';

SELECT p.payment_id, p.amount, p.payment_status, u.name, u.surname, u.email
FROM client_payments p
JOIN users u ON u.id = p.user_id
WHERE p.payment_intent_id = :stripe_payment_intent_id;

COMMIT;
-- On any failure between START TRANSACTION and COMMIT: ROLLBACK;
```

---

## 3. First Visit ("Prima Visita") Funnel

The first-visit intake form has ~20 section-completion flags on `visits`
(`reasons_completed`, `family_history_completed`, `cardio_pathology_completed`,
… `medical_values_completed`). These queries treat that as a funnel.

### 3.1 Per-client completion percentage (CTE unpivoting flags via arithmetic)

```sql
WITH section_flags AS (
  SELECT
    visit_id,
    client_id,
    visit_type,
    (reasons_completed + food_preferences_completed + family_history_completed +
     weight_history_completed + bariatric_surgery_completed + renal_pathology_completed +
     diet_history_completed + food_history_completed + cardio_pathology_completed +
     metabolic_pathology_completed + neurological_pathology_completed +
     gastro_pathology_completed + hepatic_pathology_completed +
     urological_pathology_completed + dermatologic_pathology_completed +
     thyroid_pathology_completed + respiratory_pathology_completed +
     physical_pathology_completed + other_pathology_completed +
     fibromialgia_pathology_completed + nutritional_completed +
     medical_values_completed + life_style_completed) AS sections_done,
    23 AS total_sections
  FROM visits
  WHERE visit_type = '1'
)
SELECT
  client_id,
  visit_id,
  sections_done,
  total_sections,
  ROUND(100 * sections_done / total_sections, 1) AS pct_complete,
  CASE
    WHEN sections_done = 0 THEN 'not_started'
    WHEN sections_done = total_sections THEN 'completed'
    ELSE 'in_progress'
  END AS funnel_stage
FROM section_flags
ORDER BY pct_complete DESC;
```

### 3.2 Drop-off by section (which step loses the most clients)

Among clients who started the form (`reasons_completed = 1`), the completion
rate of every later section — the lowest number is the biggest drop-off point.

```sql
SELECT
  ROUND(100 * AVG(food_preferences_completed), 1)        AS pct_food_preferences,
  ROUND(100 * AVG(family_history_completed), 1)          AS pct_family_history,
  ROUND(100 * AVG(weight_history_completed), 1)          AS pct_weight_history,
  ROUND(100 * AVG(cardio_pathology_completed), 1)        AS pct_cardio_pathology,
  ROUND(100 * AVG(metabolic_pathology_completed), 1)     AS pct_metabolic_pathology,
  ROUND(100 * AVG(neurological_pathology_completed), 1) AS pct_neurological_pathology,
  ROUND(100 * AVG(gastro_pathology_completed), 1)        AS pct_gastro_pathology,
  ROUND(100 * AVG(hepatic_pathology_completed), 1)       AS pct_hepatic_pathology,
  ROUND(100 * AVG(dermatologic_pathology_completed), 1) AS pct_dermatologic_pathology,
  ROUND(100 * AVG(thyroid_pathology_completed), 1)       AS pct_thyroid_pathology,
  ROUND(100 * AVG(respiratory_pathology_completed), 1)  AS pct_respiratory_pathology,
  ROUND(100 * AVG(life_style_completed), 1)              AS pct_life_style,
  ROUND(100 * AVG(medical_values_completed), 1)          AS pct_medical_values
FROM visits
WHERE visit_type = '1' AND reasons_completed = 1;
```

### 3.3 Time from visit start to lock (window function `AVG() OVER`)

Days between a visit's `created_at` and `updated_at` for locked first visits,
compared against the rolling average for the same month.

```sql
WITH lock_times AS (
  SELECT
    visit_id,
    client_id,
    DATE_FORMAT(created_at, '%Y-%m-01') AS start_month,
    DATEDIFF(updated_at, created_at) AS days_to_lock
  FROM visits
  WHERE visit_type = '1' AND visit_is_locked = 1
)
SELECT
  visit_id,
  client_id,
  start_month,
  days_to_lock,
  ROUND(AVG(days_to_lock) OVER (PARTITION BY start_month), 1) AS avg_days_to_lock_that_month
FROM lock_times
ORDER BY start_month, days_to_lock;
```

### 3.4 Pathology prevalence among locked first visits

Cross-references `diagnostic_notes_history` flags (already computed by the
app's pattern-flagging system) for clients whose first visit is locked.

```sql
SELECT
  ROUND(100 * AVG(has_diabetes), 1)              AS pct_diabetes,
  ROUND(100 * AVG(has_renal_failure), 1)          AS pct_renal_failure,
  ROUND(100 * AVG(has_liver_dysfunction), 1)      AS pct_liver_dysfunction,
  ROUND(100 * AVG(has_metabolic_syndrome), 1)     AS pct_metabolic_syndrome,
  ROUND(100 * AVG(has_insulin_resistance), 1)     AS pct_insulin_resistance,
  ROUND(100 * AVG(has_cardiovascular_issues), 1)  AS pct_cardiovascular_issues,
  ROUND(100 * AVG(requires_specialist), 1)        AS pct_requires_specialist,
  COUNT(*) AS locked_first_visits_analyzed
FROM diagnostic_notes_history dnh
JOIN visits v ON v.visit_id = dnh.visit_id
WHERE v.visit_type = '1' AND v.visit_is_locked = 1;
```

### 3.5 View — one-row-per-visit client summary (headline view for the portfolio)

Combines identity, payment, completion %, and diagnostic flags into a single
view — the kind of object a notebook or dashboard would `SELECT * FROM`.

```sql
CREATE OR REPLACE VIEW v_client_visit_summary AS
SELECT
  u.id AS client_id,
  u.name,
  u.surname,
  u.country,
  v.visit_id,
  v.visit_type,
  v.visit_is_locked,
  p.payment_status,
  p.amount AS amount_paid,
  ROUND(
    100 * (v.reasons_completed + v.food_preferences_completed + v.family_history_completed +
           v.weight_history_completed + v.bariatric_surgery_completed + v.renal_pathology_completed +
           v.diet_history_completed + v.food_history_completed + v.cardio_pathology_completed +
           v.metabolic_pathology_completed + v.neurological_pathology_completed +
           v.gastro_pathology_completed + v.hepatic_pathology_completed +
           v.urological_pathology_completed + v.dermatologic_pathology_completed +
           v.thyroid_pathology_completed + v.respiratory_pathology_completed +
           v.physical_pathology_completed + v.other_pathology_completed +
           v.fibromialgia_pathology_completed + v.nutritional_completed +
           v.medical_values_completed + v.life_style_completed) / 23,
    1
  ) AS pct_sections_complete,
  dnh.requires_specialist,
  dnh.critical_alert_count
FROM users u
JOIN visits v ON v.client_id = u.id
LEFT JOIN client_payments p ON p.visit_id = v.visit_id
LEFT JOIN diagnostic_notes_history dnh ON dnh.visit_id = v.visit_id
WHERE u.role_id = 6;
```

```sql
-- Then, headline query for the notebook:
SELECT * FROM v_client_visit_summary
WHERE visit_type = '1'
ORDER BY pct_sections_complete DESC;
```
