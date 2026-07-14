# DevOps Setup — Broken Oaths

Provisioned 2026-07-13 onto the existing two-box Hetzner fleet
(see `~/Documents/github/devops/` — README.md, infra.md, projects.md).
No new servers: the fleet's kamal-proxy, shared Postgres 17, SSM
secrets pattern, S3 backups, and UptimeRobot account were reused.

## Environments

| Environment | Domain | Box | Health check |
|---|---|---|---|
| prod | `broken-oaths.com` | 178.156.143.212 (Ashburn x86) | **verified** — `https://broken-oaths.com/health` returned 200 over valid TLS, 2026-07-13 |
| uat | `uat.broken-oaths.com` | 46.225.105.88 (Nuremberg ARM) | **verified** — `https://uat.broken-oaths.com/health` returned 200 over valid TLS, 2026-07-13 |

Each environment has its own database (`broken_oaths_prod` /
`broken_oaths_uat`, per-app owner users), its own SSM secrets namespace
(`/broken_oaths/{prod,uat}/*`), and its own IAM bootstrap user
(`broken-oaths-{prod,uat}-app`, SSM-read scoped to its namespace).

## DNS

Cloudflare zone `broken-oaths.com` (id `799ed6f6bd983eb0f0cd0d810c602ae9`):
unproxied A records `broken-oaths.com → 178.156.143.212` and
`uat.broken-oaths.com → 46.225.105.88` (TTL 300) so kamal-proxy's
HTTP-01 Let's Encrypt issuance works. Certificates are auto-issued and
auto-renewed by kamal-proxy; verified on first request.

## Deploys

GitHub Actions builds a multi-arch image (`ghcr.io/code-my-spec/broken_oaths`,
amd64 + arm64) on push (`.github/workflows/build.yml`); Kamal deploys from
the laptop:

- `scripts/deploy` → prod (`config/deploy.yml`)
- `scripts/deploy-uat` → UAT (`config/deploy.uat.yml`)

Health endpoints: `/up` (kamal-proxy's plain-HTTP probe) and `/health`
(public), both served by an endpoint plug ahead of Plug.Static. No
app-level force_ssl — the proxy owns TLS and redirects.

Migrations are not automatic: `kamal app exec 'bin/migrate'` (prod) /
`kamal app exec -d uat 'bin/migrate'`. Both ran 2026-07-13.

## Secrets — store-seeded, boot-fetched

`BrokenOaths.Secrets.load!/1` (Req-backed ExAws client) fetches every
parameter under `/broken_oaths/<APP_ENV>/` at boot and fails fast if the
path is empty. Kamal carries only AWS bootstrap creds + `APP_ENV` /
`AWS_REGION` / `PORT` (`.kamal/secrets-common`).

Seeded keys per env: `SECRET_KEY_BASE`, `CLOAK_KEY`, `DATABASE_URL`,
`PHX_HOST`, `POOL_SIZE`, `CODEMYSPEC_DEPLOY_KEY`, `RESEND_API_KEY`.
Pending (feature degrades gracefully until seeded): `CODEMYSPEC_CLIENT_ID`,
`CODEMYSPEC_CLIENT_SECRET` (generate on the CodeMySpec project page),
`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.

## Backups

The fleet's nightly `pg_dump` cron (03:00 UTC, both boxes) auto-discovers
databases from `pg_database`, so `broken_oaths_prod` and
`broken_oaths_uat` are included from tonight's run: local 7-day rolling
window under `/opt/shared/backups/`, shipped to
`s3://hetzner-pg-backups-889081505590/postgres/<db>/` (versioned, 90-day
lifecycle expiry, public access blocked).

## Uptime monitoring

UptimeRobot HTTP monitors (5-minute interval, 30s timeout), created via
the v3 API 2026-07-13:

- `https://broken-oaths.com/health`
- `https://uat.broken-oaths.com/health`

The fleet's `devops/scripts/uptimerobot-sync` was migrated to the v3 API
(v2 `newMonitor` now returns `access_denied` on the free plan) and both
domains added to its DOMAINS list.

## Re-runnability

- App repo: `Dockerfile`, `.github/workflows/build.yml`,
  `config/deploy*.yml`, `.kamal/secrets-common`, `scripts/deploy*`,
  `lib/broken_oaths/secrets.ex`.
- Devops repo: `scripts/provision-db` (DBs), `scripts/seed-secrets` /
  `aws ssm put-parameter --overwrite` (secrets), `scripts/uptimerobot-sync`
  (monitors), `scripts/backup-databases` (cron source). All idempotent.
