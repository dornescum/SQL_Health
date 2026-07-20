# SQL Portfolio Project — Local Setup

Companion project (separate public repo) to showcase SQL skills (CTEs, window
functions, transactions, views) to recruiters, built on an anonymized copy of
this app's MySQL database. Stack: Docker (MySQL) + Jupyter Lab + pandas +
matplotlib/plotly.

## Prerequisites

| Tool | Check | Notes |
|---|---|---|
| Docker Desktop | `docker --version` | runs the MySQL clone locally, no local MySQL install needed |
| Python 3.11+ | `python3 --version` | confirmed on this machine: `Python 3.14.2` |
| pip | `pip3 --version` | comes with Python |
| git | `git --version` | for the public repo |

## 1. Python virtual environment

```bash
cd ~/Documents/ELSE/NODE/sql-portfolio   # new project directory
python3 -m venv .venv
source .venv/bin/activate                # zsh/bash
```

Deactivate any time with `deactivate`.

## 2. Install Python dependencies

```bash
pip install --upgrade pip
pip install jupyterlab pandas sqlalchemy pymysql matplotlib plotly python-dotenv
```

Freeze once the set is stable:

```bash
pip freeze > requirements.txt
```

Re-install elsewhere with `pip install -r requirements.txt`.

## 3. MySQL via Docker

`docker-compose.yml`:

```yaml
services:
  mysql:
    image: mysql:8.0
    container_name: sql-portfolio-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: sql_portfolio
    ports:
      - "3307:3306"   # 3307 to avoid clashing with any local MySQL on 3306
    volumes:
      - ./data/dump.sql:/docker-entrypoint-initdb.d/dump.sql:ro
      - db-data:/var/lib/mysql

volumes:
  db-data:
```

```bash
docker compose up -d
docker compose logs -f mysql   # wait for "ready for connections"
```

## 4. Producing the anonymized dump

Never copy the production dump verbatim (patient PII). Export schema + synthetic/anonymized
data only:

```bash
mysqldump --no-data -u <user> -p <db> > docs/miscellaneous/dump-schema-only.sql
```

Then either:
- write an anonymization script (Python/Faker) that reads real row *shapes* but
  generates fake names/emails/DOB, or
- generate fully synthetic seed data matching the schema (recommended — zero
  PII risk, safe for a public repo).

## 5. Views

Create SQL views in the Docker DB for the queries you want to headline
(patients by pathology, doctor revenue by month, patient age/gender
distribution, etc). Keep view definitions as `.sql` files under
`sql/views/` in the new repo, applied via the docker-entrypoint init or a
small `make views` script, so the repo documents the SQL itself rather than
hiding it inside notebook cells.

## 6. Launching Jupyter Lab

```bash
source .venv/bin/activate
jupyter lab
```

Connect from a notebook with SQLAlchemy:

```python
import os
from sqlalchemy import create_engine
import pandas as pd

engine = create_engine("mysql+pymysql://root:root@127.0.0.1:3307/sql_portfolio")
df = pd.read_sql("SELECT * FROM v_patients_by_pathology", engine)
```

## 7. Repo layout (proposed)

```
sql-portfolio/
├── docker-compose.yml
├── data/
│   └── dump.sql              # schema + synthetic seed, safe to publish
├── sql/
│   ├── views/                # one .sql file per view
│   ├── ctes/                 # standalone CTE examples
│   └── transactions/         # transaction demo scripts
├── notebooks/
│   ├── 01_overview.ipynb
│   ├── 02_pathology_analysis.ipynb
│   ├── 03_doctor_earnings.ipynb
│   └── 04_forecasting.ipynb
├── requirements.txt
└── README.md
```

## Open decisions

- [ ] Confirm anonymization approach (synthetic seed vs. faker-scrubbed real shapes)
- [ ] Finalize which views/queries to headline (pathology trends, doctor
      earnings, retention/prevision forecasting)
- [ ] Decide whether to add a thin Express + Chart.js dashboard as a
      secondary artifact
