# Phixem

NFL pick board on Phoenix, SQLite, and Azure Container Apps. The home page is a LiveView week picker (1–18). Admin at `/broncosAdmin` is passphrase-gated and owns PERFECT winners and player entries.

## Local

Install Elixir 1.15+ (OTP 26+) and run:

```bash
mix setup
mix ecto.migrate
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). `/health` returns `ok`. Local `mix phx.server` does **not** run Ecto migrations on boot (`RELEASE_NAME` is unset), so run `mix ecto.migrate` after pulling new migrations.

Litestream is production-only. Dev uses `phixem.db` on disk with no Blob replica.

## SQLite, Litestream, and why max replicas is 1

The production database is a SQLite file at `DATABASE_PATH` (default `/tmp/phixem.db`). ACA consumption disks are ephemeral: scale-to-zero, a new revision, or a replaced replica wipes that file.

Litestream keeps a replica of that file in Azure Blob (`LITESTREAM_AZURE_*`, wired by Bicep).

Boot order in production:

1. ACA starts a container.
2. `Phixem.SqliteReplica.restore/0` runs **before** Ecto. If the local file is missing, it runs `litestream restore -if-replica-exists` from Blob. If a file is already on disk, restore is skipped.
3. Ecto opens SQLite and (in a release) runs migrations.
4. The Litestream child process tails the SQLite WAL and ships it to Blob while the app is up.
5. Season seed upserts week headers (see below).

A freeze or crash that fails the `/health` liveness probe gets a new container. Restore then loads **the last WAL Litestream successfully pushed**, not an in-memory snapshot of the hung process. Writes after the last replica push can be lost (usually about a second when healthy; longer if replication itself was frozen).

**`maxReplicas` must stay 1** (`infra/main.bicep`). SQLite + Litestream is a single writer. Two ACA replicas would each restore the same Blob, each write their own WAL, and then overwrite each other on the next restore (split-brain, missing rows, possible corruption). LiveView PubSub is also in-process, so boards would not stay in sync across instances.

If you ever need more than one instance, move the data to a multi-writer store (for example Azure Database for PostgreSQL), drop Litestream, and use a distributed PubSub. Vertical size on the one replica is the scaling lever for this app.

## Seeded data

Source of truth for the 18-week 2026 regular season is `priv/nfl/2026_regular_season.json`: week number, Sunday `starts_on`, matchup headers, `complete`, combined MNF tie-breaker total (`mnf_score` / `tie_breaker_value`), and ESPN winners for finished weeks.

On every boot, `Phixem.Pickem.seed_if_empty!/0` calls `seed_season!/0`, which **upserts week headers** (matchups, dates, complete flag, tie-breaker totals). Split scores like `31-10` are stored as the summed total (`41`).

PERFECT rows are different:

- If a week has **no** PERFECT row yet, seed inserts one. Finished weeks get the JSON winners and the combined tie-breaker. Incomplete weeks get an empty picks map (`{}`) so the board still has a winners row.
- If PERFECT **already exists**, seed leaves it alone. Admin saves at `/broncosAdmin` are the source of truth after first insert. Boot will not overwrite GB/BAL you entered, and will not refill week 8 after a migration cleared it.

Player entries are never created by seed. `mix run priv/repo/seeds.exs` / `Pickem.seed!/0` wipes weeks and entries, then re-runs the season upsert (dev/test only).

## What happens in production

1. Restore SQLite from Blob if the local file is missing.
2. Migrate.
3. Litestream replicates while the replica is up.
4. Upsert week headers; insert PERFECT only when missing.
5. Home LiveView reads the current week (`/?week=N`). Admin writes PERFECT and entries; scoring runs against the saved PERFECT picks.

## Deploy

### 1. Image

Push to `main` (or run **Deploy** in Actions). The image is published to GHCR:

`ghcr.io/<owner>/phixem:latest`

If the package is private, make it public under GitHub Packages, or pass a GHCR username and PAT into Bicep.

From this repo you can also run `scripts/push-and-deploy.ps1`, which pushes `main`, waits for the workflow, and updates the Container App to `ghcr.io/jasonandrewwakeman/phixem:<sha>`.

### 2. Azure resources

```bash
az group create --name phixem-rg --location eastus

# From a machine with Elixir: mix phx.gen.secret
SECRET_KEY_BASE='...'

az deployment group create \
  --resource-group phixem-rg \
  --template-file infra/main.bicep \
  --parameters \
    containerImage='ghcr.io/<owner>/phixem:latest' \
    phxHost='placeholder.example' \
    secretKeyBase="$SECRET_KEY_BASE"
```

Read the `fqdn` output, then point Phoenix at it:

```bash
az containerapp update \
  --name phixem \
  --resource-group phixem-rg \
  --set-env-vars PHX_HOST='<fqdn>'
```

### 3. Custom domain and TLS

Create a CNAME from your DuckDNS or Cloudflare hostname to the ACA FQDN. Then:

```bash
az containerapp hostname add --name phixem --resource-group phixem-rg --hostname your-name.duckdns.org
az containerapp hostname bind --name phixem --resource-group phixem-rg --hostname your-name.duckdns.org --environment phixem-env --validation-method CNAME
```

Update `PHX_HOST` to the custom hostname.

## Environment

See `.env.example`. Production needs `SECRET_KEY_BASE`, `PHX_HOST`, `DATABASE_PATH=/tmp/phixem.db`, and the `LITESTREAM_AZURE_*` values (Bicep sets these).
