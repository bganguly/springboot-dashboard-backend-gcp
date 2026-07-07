# Backend notes

## Connecting to prod Cloud SQL
- `cloud-sql-proxy` listens on `127.0.0.1:<port>` locally and tunnels to the real remote instance — psql connects to localhost, not the actual DB host.
- The `dash-db` instance is private-IP only. `cloud-sql-proxy` defaults to public IP, which fails with `config error: instance does not have IP of type "PUBLIC"`. Pass `--private-ip`.
- `--private-ip` only works with network access into that VPC (e.g. VPN). Without it, the only proven path is `seed-via-proxy.sh`'s approach: temporarily enable public IP + whitelist your IP via `gcloud sql instances patch`.
- Read-only diagnostics: `scripts/db-readonly-diagnose.sh` (fetches creds from Pulumi internally, never prints them, runs only `SELECT`/`EXPLAIN ANALYZE`).
