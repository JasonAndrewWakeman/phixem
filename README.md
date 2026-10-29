# Phixem

Phoenix hello-world on Azure Container Apps. Each visit to `/` is stored in SQLite. Litestream replicates that file to Azure Blob so the log survives scale-to-zero.

## Local

Install Elixir 1.15+ (OTP 26+) and run:

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). The list is a LiveView: open a second tab and the first tab’s timestamps update without a refresh. `/health` returns `ok` and does not add a row.

## What happens in production

1. ACA starts the container (including after idle scale-to-zero).
2. The app restores `/tmp/phixem.db` from Blob when a replica exists (`litestream restore -if-replica-exists`).
3. Ecto opens SQLite and runs migrations.
4. Litestream replicates WAL back to Blob while the app is up.
5. Connecting to `/` inserts a UTC timestamp and LiveView pushes new rows to every open tab.

Max replicas must stay at **1**.

## Deploy

### 1. Image

Push to `main` (or run **Deploy** in Actions). The image is published to GHCR:

`ghcr.io/<owner>/phixem:latest`

If the package is private, make it public under GitHub Packages, or pass a GHCR username and PAT into Bicep.

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

Use that FQDN in the browser. After the first successful request, idle the app (no traffic for a few minutes), wait, then load `/` again. You should see the original timestamps plus a new “this request” row.

### 3. Custom domain and TLS

Create a CNAME from your DuckDNS or Cloudflare hostname to the ACA FQDN. Then:

```bash
az containerapp hostname add --name phixem --resource-group phixem-rg --hostname your-name.duckdns.org
az containerapp hostname bind --name phixem --resource-group phixem-rg --hostname your-name.duckdns.org --environment phixem-env --validation-method CNAME
```

Update `PHX_HOST` to the custom hostname.

## Environment

See `.env.example`. Production needs `SECRET_KEY_BASE`, `PHX_HOST`, `DATABASE_PATH=/tmp/phixem.db`, and the `LITESTREAM_AZURE_*` values (Bicep sets these).
