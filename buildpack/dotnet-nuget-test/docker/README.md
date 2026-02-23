# NuGet Proxy E2E Test Image

E2E test for the buildpack NuGet proxy flow. Verifies that `dotnet restore` inside a Google Cloud Buildpack `pack build` picks up a proxy NuGet.Config mounted at `/workspace/NuGet.Config`.

## What it tests

This image replicates the Choreo buildpack build flow:
1. Starts podman (or uses Docker socket)
2. Reads proxy config from `/mnt/proxy-config/` (K8s secret) or env vars
3. Generates `NuGet.Config` with proxy source (and credentials if provided)
4. Runs `pack build` with `--volume .../NuGet.Config:/workspace/NuGet.Config`
5. Google buildpack (`gcr.io/buildpacks/builder:google-22`) detects .NET project
6. `dotnet restore` picks up the mounted NuGet.Config and fetches packages through the proxy

The shell functions (`_proxy_val`, `_resolve_image`, `_proxy_login`, `_setup_nuget_proxy`) are exact copies from `workflow-resources.ts`.

## Build

```bash
docker build --platform linux/amd64 -t rolandhewage/nuget-proxy-e2e:0.6.0 .
docker push rolandhewage/nuget-proxy-e2e:0.6.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack .NET SDK is amd64-only.

## Test scenarios

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
| `dotnet restore` uses proxy | During BUILDING phase — should show proxy URL, NOT nuget.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key finding: mount path

The NuGet.Config must be mounted at `/workspace/NuGet.Config` (solution-level), NOT `/workspace/.nuget/NuGet/NuGet.Config`. The Google buildpack builder sets `HOME=/home/cnb`, so the user-level config path (`~/.nuget/NuGet/NuGet.Config`) resolves to `/home/cnb/.nuget/NuGet/NuGet.Config`, not `/workspace/.nuget/...`.

## Test results (2026-02-23)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PASSED — nuget.org used, build succeeded |
| 2 | Proxy without auth (fake URL) | PASSED — `NU1301` confirms config picked up |
| 3 | Proxy without auth (real Nexus) | PASSED — fetched through Nexus proxy |
| 4 | Proxy with auth (real Nexus) | PASSED — authenticated fetch through Nexus |
