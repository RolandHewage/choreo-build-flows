# Python pip Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Python app, validating the
custom registry proxy CICD pipeline for Python/pip.

## What it tests

The Python proxy flow from `buildpack-build.ts` (lines 195-206):
- `PIP_INDEX_URL` env var passed to `pack build` via `--env`
- Credentials embedded in URL: `scheme://user:pass@host/path`
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/pip-proxy-e2e:0.1.0 .
docker push rolandhewage/pip-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Python runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-python-url` | PyPI proxy URL (e.g. `https://nexus/repository/pypi-proxy/simple/`) | Scenarios 2 & 3 |
| `pkg-python-username` | PyPI proxy username | Scenario 3 |
| `pkg-python-password` | PyPI proxy password | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed. Does NOT need outbound access to `gcr.io`.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-pip \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + PyPI proxy without auth (scenario 2)
kubectl create secret generic test-proxy-config-pip-anon \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-python-url=https://your-proxy/repository/pypi-proxy/simple/

# ACR + PyPI proxy with auth (scenario 3)
kubectl create secret generic test-proxy-config-pip-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-python-url=https://your-proxy/repository/pypi-proxy/simple/ \
  --from-literal=pkg-python-username=user \
  --from-literal=pkg-python-password=pass
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no pip proxy config).

```bash
kubectl run pip-test --rm -it --restart=Never \
  --image=rolandhewage/pip-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"pip-test",
        "image":"rolandhewage/pip-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-pip","optional":true}}]
    }
  }'
```

**Expected:** `pip install` fetches from pypi.org, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2. Proxy without auth

Verifies `PIP_INDEX_URL` is passed as env var to `pack build`.

```bash
kubectl run pip-test --rm -it --restart=Never \
  --image=rolandhewage/pip-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"pip-test",
        "image":"rolandhewage/pip-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-pip-anon","optional":true}}]
    }
  }'
```

**Expected:** `--env PIP_INDEX_URL=<url>` in pack build command. With a fake URL, pip fails. With a real proxy, build succeeds.

### 3. Proxy with auth

Verifies credentials are embedded in the `PIP_INDEX_URL` as `scheme://user:pass@host/path`.

```bash
kubectl run pip-test --rm -it --restart=Never \
  --image=rolandhewage/pip-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"pip-test",
        "image":"rolandhewage/pip-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-pip-auth","optional":true}}]
    }
  }'
```

**Expected:** `--env PIP_INDEX_URL=https://user:pass@your-proxy/repository/pypi-proxy/simple/` in pack build command.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-pip test-proxy-config-pip-anon test-proxy-config-pip-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-python-url
# e.g., https://abc123.ngrok-free.app/repository/pypi-proxy/simple/
```

### Nexus setup for PyPI proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **pypi (proxy)**
2. **Name:** `pypi-proxy`, **Remote storage:** `https://pypi.org/`
3. Repository URL: `http://localhost:8081/repository/pypi-proxy/simple/`
4. The trailing `/simple/` is required — pip expects the PEP 503 simple API format

### Obtaining credentials for PyPI proxy

Use normal Nexus user credentials (username/password) — no special token needed.

| K8s Secret key | Value |
|---|---|
| `pkg-python-url` | Nexus PyPI proxy URL (e.g. `http://localhost:8081/repository/pypi-proxy/simple/`) |
| `pkg-python-username` | Nexus username (e.g. `admin`) |
| `pkg-python-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD embeds credentials directly in the URL as `scheme://user:pass@host/path` and passes it via `--env PIP_INDEX_URL`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `PIP_INDEX_URL` set | `_LANG_ENV` line shows `--env PIP_INDEX_URL=...` |
| Credentials in URL (scenario 3) | URL contains `://user:pass@host` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| `pip install` uses proxy | During BUILDING phase — should show proxy URL, NOT pypi.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from NuGet test

| Aspect | NuGet (.NET) | Python (pip) |
|---|---|---|
| Proxy mechanism | NuGet.Config file mounted as volume | `PIP_INDEX_URL` env var |
| Variable accumulated | `_LANG_VOLUMES` | `_LANG_ENV` |
| Auth embedding | XML `<packageSourceCredentials>` | URL-embedded `scheme://user:pass@host` |
| Detection file | `.csproj` | `requirements.txt` |

## Test results

### 0.1.0 (2026-03-04)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — pypi.org used, build succeeded |
| 2a | Proxy without auth (fake URL) | PASSED — `Name or service not known` confirms PIP_INDEX_URL picked up |
| 2b | Proxy without auth (real Nexus via ngrok) | PASSED — anonymous fetch through Nexus proxy |
| 3 | Proxy with auth (real Nexus via ngrok) | PASSED — authenticated fetch through Nexus proxy, credentials masked in logs |
