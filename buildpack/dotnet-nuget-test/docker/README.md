# NuGet Proxy E2E Test Image

E2E test for the buildpack NuGet proxy flow. Verifies that `dotnet restore` inside a Google Cloud Buildpack `pack build` picks up a proxy NuGet.Config mounted at `/home/cnb/.nuget/NuGet/NuGet.Config`.

## What it tests

This image replicates the Choreo buildpack build flow:
1. Starts podman (or uses Docker socket)
2. Reads proxy config from `/mnt/proxy-config/` (K8s Secret volume mount)
3. Generates `NuGet.Config` with proxy source (and credentials if provided)
4. Runs `pack build` with `--volume .../NuGet.Config:/home/cnb/.nuget/NuGet/NuGet.Config`
5. Google buildpack detects .NET project
6. `dotnet restore` picks up the mounted NuGet.Config and fetches packages through the proxy

The shell functions (`_proxy_val`, `_resolve_image`, `_proxy_login`, `_setup_nuget_proxy`) are exact copies from `workflow-resources.ts`.

## Image versions

| Version | Builder source | Entrypoint | Notes |
|---|---|---|---|
| `0.6.0` | `gcr.io/buildpacks/builder:google-22` | `entrypoint-0.6.0.sh` | Requires outbound access to `gcr.io` |
| `0.11.0` | Resolved via `_resolve_image` (default: `choreoprivateacr.azurecr.io/...` → rewritten by `oci-buildpacks-url`) | `entrypoint-0.11.0.sh` | All config via K8s Secret mount at `/mnt/proxy-config/` |
| `0.12.0` | Same as 0.11.0 | `entrypoint.sh` | Added `--env GOOGLE_RUNTIME_IMAGE_REGION=us` to match production flow. Fixed NuGet.Config mount path to `/home/cnb/.nuget/NuGet/NuGet.Config` (matching PR #2495). |

> **Note:** The active `entrypoint.sh` (used by the Dockerfile) is the 0.12.0 version. Previous versions are preserved as `entrypoint-0.11.0.sh` and `entrypoint-0.6.0.sh` for reference.

## Build

```bash
# 0.12.0 — ACR builder, K8s Secret mount, GOOGLE_RUNTIME_IMAGE_REGION=us
docker build --platform linux/amd64 -t rolandhewage/nuget-proxy-e2e:0.12.0 .
docker push rolandhewage/nuget-proxy-e2e:0.12.0
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

### 0.12.0 — no env vars needed

All configuration is provided via K8s Secret volume mount at `/mnt/proxy-config/`. See [Test scenarios — 0.12.0](#test-scenarios--0120-acr-builder-k8s-secret-mount) below for how to create the secret and mount it.

Builder and run images start as `choreoprivateacr.azurecr.io/...` (PDP defaults) and are resolved through `_resolve_image` using `oci-buildpacks-url` from the K8s Secret — matching the production flow in `buildpack-build.ts`.

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

## Test scenarios — 0.12.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed. Does NOT need outbound access to `gcr.io`.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + NuGet proxy without auth (scenario 2)
kubectl create secret generic test-proxy-config-nuget \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-nuget-url=https://your-proxy/v3/index.json

# ACR + NuGet proxy with auth (scenario 3)
kubectl create secret generic test-proxy-config-nuget-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-nuget-url=https://your-proxy/v3/index.json \
  --from-literal=pkg-nuget-username=user \
  --from-literal=pkg-nuget-password=pass
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no NuGet proxy config).

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.12.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"nuget-test",
        "image":"rolandhewage/nuget-proxy-e2e:0.12.0",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config","optional":true}}]
    }
  }'
```

**Expected:** `dotnet restore` fetches from nuget.org, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2. Proxy without auth

Verifies NuGet.Config is generated and picked up by `dotnet restore`.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.12.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"nuget-test",
        "image":"rolandhewage/nuget-proxy-e2e:0.12.0",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-nuget","optional":true}}]
    }
  }'
```

**Expected:** `dotnet restore` uses the proxy URL. With a fake URL, fails with `NU1301`. With a real proxy, build succeeds.

### 3. Proxy with auth

Verifies NuGet.Config includes `<packageSourceCredentials>` with username/password.

```bash
kubectl run nuget-test --rm -it --restart=Never \
  --image=rolandhewage/nuget-proxy-e2e:0.12.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"nuget-test",
        "image":"rolandhewage/nuget-proxy-e2e:0.12.0",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-nuget-auth","optional":true}}]
    }
  }'
```

**Expected:** Same as above, with credentials sent to the proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config test-proxy-config-nuget test-proxy-config-nuget-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-nuget-url
# e.g., https://abc123.ngrok-free.app/repository/nuget-proxy/index.json
```

### Nexus setup for NuGet proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **nuget (proxy)**
2. **Name:** `nuget-proxy`, **Protocol version:** `NuGet V3`, **Remote storage:** `https://api.nuget.org/v3/index.json`
3. Repository URL: `http://localhost:8081/repository/nuget-proxy/index.json`
4. The `/index.json` suffix is required — NuGet V3 uses a service index endpoint

### Obtaining credentials for NuGet proxy

Use normal Nexus user credentials (username/password). NuGet also supports API keys, but for Nexus proxy the standard user credentials work.

| K8s Secret key | Value |
|---|---|
| `pkg-nuget-url` | Nexus NuGet proxy URL (e.g. `http://localhost:8081/repository/nuget-proxy/index.json`) |
| `pkg-nuget-username` | Nexus username (e.g. `admin`) |
| `pkg-nuget-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD generates a `NuGet.Config` XML file with `<packageSourceCredentials>` and mounts it at `/home/cnb/.nuget/NuGet/NuGet.Config` via `_LANG_VOLUMES`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| NuGet.Config generated correctly | After `Generated NuGet.Config:` |
| Volume mount path is correct | `_LANG_VOLUMES` should show `:/home/cnb/.nuget/NuGet/NuGet.Config` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| `dotnet restore` uses proxy | During BUILDING phase — should show proxy URL, NOT nuget.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key finding: mount path

The NuGet.Config must be mounted at `/home/cnb/.nuget/NuGet/NuGet.Config` (user-level config). The Google buildpack builder sets `HOME=/home/cnb`, so `~/.nuget/NuGet/NuGet.Config` resolves to this path. The old mount path `/workspace/NuGet.Config` caused buildpack exporter permission errors (fixed in PR #2495).

## Key finding: run image resolution

The builder image's embedded metadata points to `gcr.io/buildpacks/google-22/run:latest`, but the E2E test uses `choreoprivateacr.azurecr.io/buildpacks/google-22/run:<tag>` as the original (PDP default). `_resolve_image` reads `oci-buildpacks-url` from the K8s Secret and rewrites the registry prefix. The resolved image is passed via `--run-image` to override the builder's embedded default.

## Test results

### 0.6.0 (2026-02-23)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PASSED — nuget.org used, build succeeded |
| 2 | Proxy without auth (fake URL) | PASSED — `NU1301` confirms config picked up |
| 3 | Proxy without auth (real Nexus) | PASSED — fetched through Nexus proxy |
| 4 | Proxy with auth (real Nexus) | PASSED — authenticated fetch through Nexus |

### 0.11.0 (PENDING)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PENDING |
| 2 | Proxy without auth | PENDING |
| 3 | Proxy with auth | PENDING |

### 0.12.0 (2026-04-02)

Added `GOOGLE_RUNTIME_IMAGE_REGION=us` and fixed NuGet.Config mount path to `/home/cnb/.nuget/NuGet/NuGet.Config`.

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — SDK from `us-docker.pkg.dev`, NuGet from nuget.org |
| 2 | Proxy without auth | PASSED — SDK from `us-docker.pkg.dev`, NuGet through Nexus proxy |
| 3 | Proxy with auth | PASSED — SDK from `us-docker.pkg.dev`, NuGet through Nexus proxy with credentials |
