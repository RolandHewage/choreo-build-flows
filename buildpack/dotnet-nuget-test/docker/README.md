# NuGet Proxy E2E Test Image

E2E test for the buildpack NuGet proxy flow. Verifies that `dotnet restore` inside a Google Cloud Buildpack `pack build` picks up a proxy NuGet.Config mounted at `/workspace/NuGet.Config`.

## What it tests

This image replicates the Choreo buildpack build flow:
1. Starts podman (or uses Docker socket)
2. Reads proxy config from `/mnt/proxy-config/` (K8s secret) or env vars
3. Generates `NuGet.Config` with proxy source (and credentials if provided)
4. Runs `pack build` with `--volume .../NuGet.Config:/workspace/NuGet.Config`
5. Google buildpack detects .NET project
6. `dotnet restore` picks up the mounted NuGet.Config and fetches packages through the proxy

The shell functions (`_proxy_val`, `_resolve_image`, `_proxy_login`, `_setup_nuget_proxy`) are exact copies from `workflow-resources.ts`.

## Image versions

| Version | Builder source | Entrypoint | Notes |
|---|---|---|---|
| `0.6.0` | `gcr.io/buildpacks/builder:google-22` | `entrypoint-0.6.0.sh` | Requires outbound access to `gcr.io` |
| `0.9.0` | `choreoprivateacr.azurecr.io/buildpacks/builder:google-22` | `entrypoint-0.9.0.sh` (= `entrypoint.sh`) | Requires ACR credentials via `OCI_BUILDPACKS_*` env vars |

> **Note:** The active `entrypoint.sh` (used by the Dockerfile) is the 0.9.0 version.

## Build

```bash
# 0.6.0 — gcr.io builder (copy entrypoint-0.6.0.sh → entrypoint.sh first)
cp entrypoint-0.6.0.sh entrypoint.sh
docker build --platform linux/amd64 -t rolandhewage/nuget-proxy-e2e:0.6.0 .
docker push rolandhewage/nuget-proxy-e2e:0.6.0

# 0.9.0 — ACR builder (copy entrypoint-0.9.0.sh → entrypoint.sh first)
cp entrypoint-0.9.0.sh entrypoint.sh
docker build --platform linux/amd64 -t rolandhewage/nuget-proxy-e2e:0.9.0 .
docker push rolandhewage/nuget-proxy-e2e:0.9.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack .NET SDK is amd64-only.

## Environment variables

### 0.6.0 env vars

| Env var | Purpose | Required |
|---|---|---|
| `PROXY_NUGET_URL` | NuGet proxy URL | Scenarios 2 & 3 only |
| `PROXY_NUGET_USERNAME` | NuGet proxy username | Scenario 3 only |
| `PROXY_NUGET_PASSWORD` | NuGet proxy password | Scenario 3 only |
| `BUILDER` | Override builder image | No (default: `gcr.io/buildpacks/builder:google-22`) |

### 0.9.0 env vars (all of 0.6.0 plus)

| Env var | Purpose | Required |
|---|---|---|
| `OCI_BUILDPACKS_URL` | ACR registry host (e.g., `choreoprivateacr.azurecr.io`) | Always |
| `OCI_BUILDPACKS_USERNAME` | ACR username | Always |
| `OCI_BUILDPACKS_PASSWORD` | ACR password | Always |
| `PROXY_NUGET_URL` | NuGet proxy URL | Scenarios 2 & 3 only |
| `PROXY_NUGET_USERNAME` | NuGet proxy username | Scenario 3 only |
| `PROXY_NUGET_PASSWORD` | NuGet proxy password | Scenario 3 only |
| `BUILDER` | Override builder image | No (default: `choreoprivateacr.azurecr.io/buildpacks/builder:google-22`) |
| `RUN_IMAGE` | Override run image | No (default: `choreoprivateacr.azurecr.io/buildpacks/google-22/run:latest`) |

---

## Test scenarios — 0.6.0 (gcr.io builder)

> Requires cluster with outbound access to `gcr.io`.

### 1. No-proxy (default flow baseline)

Verifies builds work unchanged when no proxy secret is mounted.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.6.0 \
  --overrides='{"spec":{"containers":[{"name":"nuget-test","image":"rolandhewage/nuget-proxy-e2e:0.6.0","securityContext":{"privileged":true}}]}}'
```

**Expected:** `dotnet restore` fetches from nuget.org, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2. Proxy without auth

Verifies NuGet.Config is generated and picked up by `dotnet restore`.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.6.0 \
  --overrides='{"spec":{"containers":[{"name":"nuget-test","image":"rolandhewage/nuget-proxy-e2e:0.6.0","securityContext":{"privileged":true},"env":[{"name":"PROXY_NUGET_URL","value":"https://your-proxy/v3/index.json"}]}]}}'
```

**Expected:** `dotnet restore` uses the proxy URL. With a fake URL, fails with `NU1301`. With a real proxy, build succeeds.

### 3. Proxy with auth

Verifies NuGet.Config includes `<packageSourceCredentials>` with username/password.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.6.0 \
  --overrides='{"spec":{"containers":[{"name":"nuget-test","image":"rolandhewage/nuget-proxy-e2e:0.6.0","securityContext":{"privileged":true},"env":[{"name":"PROXY_NUGET_URL","value":"https://your-proxy/v3/index.json"},{"name":"PROXY_NUGET_USERNAME","value":"user"},{"name":"PROXY_NUGET_PASSWORD","value":"pass"}]}]}}'
```

**Expected:** Same as above, with credentials sent to the proxy.

---

## Test scenarios — 0.9.0 (ACR builder)

> Requires ACR credentials. Does NOT need outbound access to `gcr.io`.

### 1. No-proxy (default flow baseline)

Verifies builds work unchanged when no proxy secret is mounted. ACR credentials are still required to pull the builder/run images.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.9.0 \
  --overrides='{
    "spec":{"containers":[{
      "name":"nuget-test",
      "image":"rolandhewage/nuget-proxy-e2e:0.9.0",
      "securityContext":{"privileged":true},
      "env":[
        {"name":"OCI_BUILDPACKS_URL","value":"choreoprivateacr.azurecr.io"},
        {"name":"OCI_BUILDPACKS_USERNAME","value":"<acr-username>"},
        {"name":"OCI_BUILDPACKS_PASSWORD","value":"<acr-password>"}
      ]
    }]}
  }'
```

**Expected:** `dotnet restore` fetches from nuget.org, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2. Proxy without auth

Verifies NuGet.Config is generated and picked up by `dotnet restore`.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.9.0 \
  --overrides='{
    "spec":{"containers":[{
      "name":"nuget-test",
      "image":"rolandhewage/nuget-proxy-e2e:0.9.0",
      "securityContext":{"privileged":true},
      "env":[
        {"name":"OCI_BUILDPACKS_URL","value":"choreoprivateacr.azurecr.io"},
        {"name":"OCI_BUILDPACKS_USERNAME","value":"<acr-username>"},
        {"name":"OCI_BUILDPACKS_PASSWORD","value":"<acr-password>"},
        {"name":"PROXY_NUGET_URL","value":"https://your-proxy/v3/index.json"}
      ]
    }]}
  }'
```

**Expected:** `dotnet restore` uses the proxy URL. With a fake URL, fails with `NU1301`. With a real proxy, build succeeds.

### 3. Proxy with auth

Verifies NuGet.Config includes `<packageSourceCredentials>` with username/password.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.9.0 \
  --overrides='{
    "spec":{"containers":[{
      "name":"nuget-test",
      "image":"rolandhewage/nuget-proxy-e2e:0.9.0",
      "securityContext":{"privileged":true},
      "env":[
        {"name":"OCI_BUILDPACKS_URL","value":"choreoprivateacr.azurecr.io"},
        {"name":"OCI_BUILDPACKS_USERNAME","value":"<acr-username>"},
        {"name":"OCI_BUILDPACKS_PASSWORD","value":"<acr-password>"},
        {"name":"PROXY_NUGET_URL","value":"https://your-proxy/v3/index.json"},
        {"name":"PROXY_NUGET_USERNAME","value":"user"},
        {"name":"PROXY_NUGET_PASSWORD","value":"pass"}
      ]
    }]}
  }'
```

**Expected:** Same as above, with credentials sent to the proxy.

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL as PROXY_NUGET_URL
# e.g., https://abc123.ngrok-free.app/repository/nuget-proxy/index.json
```

## What to check in logs

| Check | Where in output |
|---|---|
| NuGet.Config generated correctly | After `Generated NuGet.Config:` |
| Volume mount path is correct | `_LANG_VOLUMES` should show `:/workspace/NuGet.Config` |
| ACR login succeeded (0.9.0 only) | After `Logging into proxy mirror:` |
| `dotnet restore` uses proxy | During BUILDING phase — should show proxy URL, NOT nuget.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key finding: mount path

The NuGet.Config must be mounted at `/workspace/NuGet.Config` (solution-level), NOT `/workspace/.nuget/NuGet/NuGet.Config`. The Google buildpack builder sets `HOME=/home/cnb`, so the user-level config path (`~/.nuget/NuGet/NuGet.Config`) resolves to `/home/cnb/.nuget/NuGet/NuGet.Config`, not `/workspace/.nuget/...`.

## Key finding: run image override (0.9.0)

Even when the builder image is mirrored to ACR, its embedded metadata still points to `gcr.io/buildpacks/google-22/run:latest`. The `--run-image` flag in `pack build` overrides this to pull the run image from ACR instead.

## Test results

### 0.6.0 (2026-02-23)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PASSED — nuget.org used, build succeeded |
| 2 | Proxy without auth (fake URL) | PASSED — `NU1301` confirms config picked up |
| 3 | Proxy without auth (real Nexus) | PASSED — fetched through Nexus proxy |
| 4 | Proxy with auth (real Nexus) | PASSED — authenticated fetch through Nexus |

### 0.9.0 (2026-03-03)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PENDING |
| 2 | Proxy without auth | PENDING |
| 3 | Proxy with auth | PENDING |
