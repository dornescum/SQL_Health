# SQL_Health

A SQL portfolio project built on an anonymized clone of a real nutrition/health
app's MySQL database. It showcases CTEs, window functions, transactions, and
views through queries scoped to the app's "client" domain (profiles, payments,
first-visit intake funnel), explored via Jupyter notebooks.

Stack: Docker (MySQL) + Jupyter Lab + pandas + SQLAlchemy + matplotlib/plotly.

## Repo layout

```
docs/                 Setup notes and the SQL query reference
  project.md              Local setup: Docker MySQL, Python env, Jupyter
  Client_Querires.md       Query reference (CTEs, window functions, a
                           transaction, and a view) scoped to client data
notebooks/            Jupyter notebooks that run the queries against the DB
sql/                  Query files organized by SQL feature showcased
  ctes/
  views/
  transactions/
data/                 Local DB dump (gitignored — never commit real data)
requirements.txt      Python dependencies
```

## Setup

Full walkthrough in [`docs/project.md`](docs/project.md). Short version:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

docker compose up -d          # starts MySQL, loads data/dump.sql
cp .env.example .env           # fill in DB credentials
jupyter lab
```

## Notebooks

| Notebook | Description |
|---|---|
| `01_overview.ipynb` | Connects via the read-only analyst account and pulls the patient/cardio master view |
| `02_allUsers.ipynb` | Lists all users and charts them by sex |
| `03_allUsersWomen.ipynb` | Filters users to `sex = 2` |
| `04_activeClientsByCountryAndTown.ipynb` | Active clients grouped by country/town (query 1.1 in the reference doc) |

## Query reference

[`docs/Client_Querires.md`](docs/Client_Querires.md) is the canonical list of
queries this project implements, grouped by domain:

1. **User / client profile** — active clients by location, signups over time
   with running totals, blocked-client audit, activity-recency ranking
2. **Payments & revenue** — monthly revenue trends, payment status funnel,
   visit-eligibility rules, top-paying clients, a payment-confirmation
   transaction
3. **First-visit ("Prima Visita") funnel** — per-client completion %,
   drop-off by section, time-to-lock, pathology prevalence, and a
   headline `v_client_visit_summary` view

Each query is written to be copy-pasted into `sql/ctes/`, `sql/views/`, or
`sql/transactions/`, or run directly in a notebook.

## Data privacy

The database is a Docker-local clone seeded from `data/dump.sql`
(gitignored). Only anonymized or fully synthetic data is used — no real
patient data is ever committed to this repo.
