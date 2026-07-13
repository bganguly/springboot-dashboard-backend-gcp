# Dashboard Backend — Spring Boot + GCP Cloud Run

Production-grade **Java 21 / Spring Boot 4** REST API delivering sub-second responses across
4 million orders: full-text trigram search, pre-aggregated analytics tables, serverless autoscaling,
and declarative Pulumi IaC on GCP.

Sister repo: [dashboard-frontend-gcp](https://github.com/bganguly/dashboard-frontend-gcp)

---

| | |
|---|---|
| **Java / Spring Boot back-end** | Spring Boot 4, Java 21, NamedParameterJdbcTemplate, Flyway |
| **PostgreSQL — SQL, DML/DDL, performance tuning** | Cloud SQL PG 16; Flyway DDL migrations; GIN trigram index; pre-aggregated summary tables for sub-second chart queries on 4 M rows |
| **Serverless / cloud-native computing** | Cloud Run — min-instances: 0, scales to zero, Direct VPC Egress to private Postgres |
| **IaC (Terraform equivalent)** | Pulumi TypeScript (`infra/index.ts`) — VPC, GCE Postgres VM, Cloud Run service, IAM, Secret Manager, Artifact Registry all declared |
| **CI/CD pipelines** | `deploy.sh` — build → push to Artifact Registry → `pulumi up --yes`; seed pipeline in `scripts/seed-via-proxy.sh` |
| **Secrets management** | GCP Secret Manager; `DATABASE_URL` injected at runtime via `secretKeyRef`, never stored in image or env file |
| **Networking, storage, DB architecture** | Private VPC, Direct VPC Egress, Private Service Connect for Cloud SQL, `db-custom-4-16384`, disk autoresize |
| **BFF / integration layer** | Nginx frontend proxies `/api/*` to Cloud Run backend (TLS + SNI); Spring Boot orchestrates REST + DB |
| **RESTful APIs / microservices** | Two independent Cloud Run services; paginated list endpoint + aggregates endpoint |
| **Performance optimization** | Sub-second ILIKE search on 4 M rows via GIN trigram index; pre-aggregated daily tables cut chart query time from seconds to milliseconds |
| **System design diagrams** | See architecture section below |

---


## Scale & Performance

> **4 M+ orders** in Cloud SQL PostgreSQL 16 — sub-second full-text search via GIN trigram index on a denormalized `search_text` column; millisecond chart aggregates via pre-aggregated summary tables; zero sequential scans on the hot path.

```
Browser ──HTTPS──► Nginx / Cloud Run ──proxy /api/* (SNI)──► Spring Boot / Cloud Run ──VPC──► Cloud SQL PG 16
                   dash-frontend                             dash-backend                      dash-db
                   0–3 instances                            1–5 instances                     4 M+ rows · GIN index
                                    ▲─────────────── Pulumi TypeScript IaC ───────────────────▲
```

---

## Running

```bash
./scripts/deploy.sh      # local [1] or GCP [2]
./scripts/infra-down.sh  # stop local [1] or teardown GCP [2]
```

### Scheduled warm-instance window (8am–5pm Pacific)

One warm backend instance during demo hours; scales to zero overnight. `dash-lite-` → `dash-full-` for the full tier.

```bash
gcloud scheduler jobs pause  dash-lite-scale-{up,down}-backend --location us-central1 --project bikram-java
gcloud scheduler jobs resume dash-lite-scale-{up,down}-backend --location us-central1 --project bikram-java
gcloud scheduler jobs run    dash-lite-scale-up-backend        --location us-central1 --project bikram-java
gcloud scheduler jobs run    dash-lite-scale-down-backend      --location us-central1 --project bikram-java
```

---

## Live Service

| | URL |
|---|---|
| **Backend API** | https://dash-backend-7u2hpcwtmq-uc.a.run.app |

```bash
# local
curl http://localhost:8080/actuator/health
curl "http://localhost:8080/api/orders?page=1&size=3" | jq .total
curl "http://localhost:8080/api/orders?q=sara+carter&page=1&size=3" | jq '.data[].customer'

# GCP (if deployed)
BASE=https://dash-backend-7u2hpcwtmq-uc.a.run.app
curl "$BASE/actuator/health"
curl "$BASE/api/orders?page=1&size=3" | jq .total
```

---

## Architecture / Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              GCP Project                                │
│                                                                         │
│   Artifact Registry                                                     │
│   ┌──────────────────┐                                                  │
│   │  frontend image  │                                                  │
│   │  backend image   │                                                  │
│   └──────────────────┘                                                  │
│           │ image pull                  Pulumi TypeScript (IaC)         │
│           ▼                             manages all resources below     │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │                       dash-vpc (private)                      │     │
│   │                                                               │     │
│   │  Cloud Run: dash-frontend          Cloud Run: dash-backend    │     │
│   │  ┌─────────────────────────┐       ┌──────────────────────┐   │     │
│   │  │ Nginx (port 80)         │       │ Spring Boot (8080)   │   │     │
│   │  │ • serves Vite dist      │ HTTPS │ • REST /api/*        │   │     │
│   │  │ • proxies /api/* ───────┼──────►│ • Flyway migrations  │   │     │
│   │  │   proxy_ssl_server_name │  SNI  │ • NamedParameterJdbc │   │     │
│   │  │   on (SNI required)     │       │ • 1–5 instances      │   │     │
│   │  │ • 0–3 instances         │       └──────────┬───────────┘   │     │
│   │  └─────────────────────────┘                  │               │     │
│   │           ▲                          Direct VPC Egress        │     │
│   │           │ HTTPS                    (private IP, no proxy)   │     │
│   └───────────┼──────────────────────────────────┼───────────────┘     │
│               │                                   │                     │
│           Browser                    ┌────────────▼───────────┐        │
│                                      │  Cloud SQL PG 16       │        │
│                                      │  dash-db               │        │
│                                      │  • orders (4 M rows)   │        │
│                                      │  • GIN trigram index   │        │
│                                      │    on search_text      │        │
│                                      │  • pre-agg summary     │        │
│                                      │    tables for charts   │        │
│                                      │  • Flyway V1–V4        │        │
│                                      └────────────────────────┘        │
│                                                                         │
│   Secret Manager                                                        │
│   ┌──────────────────────┐                                              │
│   │ dash-database-url    │◄── secretKeyRef (backend container env)      │
│   └──────────────────────┘                                              │
└─────────────────────────────────────────────────────────────────────────┘

Deploy flow
───────────
local machine
  └─ deploy.sh
       ├─ docker build + push → Artifact Registry
       └─ pulumi up --yes
            ├─ VPC / subnets / firewall
            ├─ Cloud SQL instance + db + user
            ├─ Secret Manager secret (DATABASE_URL)
            ├─ Cloud Run backend (startup probe: 15 min for Flyway)
            └─ Cloud Run frontend (BACKEND_URL env from backend URI)

Seed flow (one-time, 4 M orders from S3 dump)
─────────────────────────────────────────────
scripts/seed-via-proxy.sh
  ├─ whitelist local public IP on Cloud SQL authorized networks
  ├─ pg_restore directly on port 5432
  └─ remove authorized network on exit (cleanup trap)
```

### Key design decisions

| Concern | Approach |
|---|---|
| **Search performance** | Denormalized `search_text` column (name + notes + total + id + status + region + date) with one GIN trigram index — sub-second ILIKE on 4 M rows, single index hit per token, no cross-table OR |
| **Chart performance** | Pre-aggregated `daily_summary`, `daily_customer_category_summary`, `daily_status_category_summary`, `daily_filter_category_summary` — sub-second chart aggregates, queries never touch raw `orders` |
| **Trigger maintenance** | `fn_order_search_text()` (BEFORE INSERT/UPDATE on orders) + `fn_customer_name_to_orders()` (AFTER UPDATE on customers) keep `search_text` current without application-level logic |
| **Startup resilience** | Cloud Run startup probe with `failureThreshold: 60` × `periodSeconds: 15` = 15 min — survives long Flyway migrations (e.g. UPDATE + CREATE INDEX on 4 M rows) |
| **Zero-credential deploys** | Backend SA with `roles/secretmanager.secretAccessor` + `roles/cloudsql.client`; no passwords in code or Docker image |
