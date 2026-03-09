# Go Module Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Go app, validating the
custom registry proxy CICD pipeline for Go modules.

## What it tests

The Go proxy flow from `buildpack-build.ts`:
- `GOPROXY` env var passed to `pack build` via `--env`
- `.netrc` auth: `pkg-go-username`/`pkg-go-password` → `.netrc` file mounted at `/home/cnb/.netrc`
- `GONOSUMDB=*` set when auth is configured (skip checksum DB for all modules)
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/go-proxy-e2e:0.1.0 .
docker push rolandhewage/go-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Go runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-go-url` | Go module proxy URL (e.g. `https://nexus/repository/go-proxy/,direct`) | Scenarios 2 & 3 |
| `pkg-go-username` | Go proxy username (for authenticated proxies) | Scenario 3 |
| `pkg-go-password` | Go proxy password (for authenticated proxies) | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount, .netrc auth)

> All config via K8s Secret volume mount. No env vars needed. Does NOT need outbound access to `gcr.io`.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-go \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + Go proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-go-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-go-url=https://your-proxy/repository/go-proxy/,direct

# ACR + Go proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-go-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-go-url=https://your-proxy/repository/go-proxy/,direct \
  --from-literal=pkg-go-username=<nexus-username> \
  --from-literal=pkg-go-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no Go proxy config).

```bash
kubectl run go-test --rm -it --restart=Never \
  --image=rolandhewage/go-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"go-test",
        "image":"rolandhewage/go-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-go","optional":true}}]
    }
  }'
```

**Expected:** `go mod download` fetches from `proxy.golang.org`, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify GOPROXY is picked up)

Verifies `GOPROXY` is passed as env var to `pack build`.

```bash
kubectl run go-test --rm -it --restart=Never \
  --image=rolandhewage/go-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"go-test",
        "image":"rolandhewage/go-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-go-proxy","optional":true}}]
    }
  }'
```

**Expected:** `--env GOPROXY=<url>` in pack build command. With a fake URL, module download fails. With a real proxy, build succeeds.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus Go proxy URL in the secret.

**Expected:** Go modules (`go-chi/chi`) fetched through Nexus Go proxy.

### 3a. Proxy with auth — fake URL (verify .netrc generation)

Verifies `.netrc` file is generated and mounted, `GONOSUMDB=*` is set.

```bash
kubectl run go-test --rm -it --restart=Never \
  --image=rolandhewage/go-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"go-test",
        "image":"rolandhewage/go-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-go-auth","optional":true}}]
    }
  }'
```

**Expected:** `_LANG_VOLUMES` includes `--volume /tmp/go-proxy-auth/.netrc:/home/cnb/.netrc`, `_LANG_ENV` includes `--env GONOSUMDB=*`. With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus Go proxy URL and credentials in the secret.

**Expected:** `.netrc` used for authentication, Go modules fetched through authenticated Nexus Go proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-go test-proxy-config-go-proxy test-proxy-config-go-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-go-url
# e.g., https://abc123.ngrok-free.app/repository/go-proxy/,direct
```

### Nexus setup for Go proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **go (proxy)**
2. **Name:** `go-proxy`, **Remote storage:** `https://proxy.golang.org`
3. Repository URL: `http://localhost:8081/repository/go-proxy/`
4. Use `<url>,direct` as `pkg-go-url` to allow fallback if the proxy doesn't have the module

### Obtaining credentials for Go proxy

Go does **not** have a `go login` command. Use normal Nexus user credentials (username/password) — no special token needed.

| K8s Secret key | Value |
|---|---|
| `pkg-go-url` | Nexus Go proxy repo URL (e.g. `http://localhost:8081/repository/go-proxy/,direct`) |
| `pkg-go-username` | Nexus username (e.g. `admin`) |
| `pkg-go-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD generates a `.netrc` file from these credentials and mounts it at `/home/cnb/.netrc`. Go reads `.netrc` automatically for HTTP Basic Auth.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `GOPROXY` set | `_LANG_ENV` line shows `--env GOPROXY=...` |
| `.netrc` generated (auth) | `_LANG_VOLUMES` line shows `--volume /tmp/go-proxy-auth/.netrc:/home/cnb/.netrc` |
| `GONOSUMDB` set (auth) | `_LANG_ENV` line shows `--env GONOSUMDB=*` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| `go mod download` uses proxy | During BUILDING phase — should show proxy URL, NOT proxy.golang.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from Python test

| Aspect | Python (pip) | Go |
|---|---|---|
| Proxy mechanism | `PIP_INDEX_URL` env var with embedded credentials | `GOPROXY` env var (URL only) |
| Auth handling | Credentials embedded in URL: `scheme://user:pass@host` | `.netrc` file mounted at `/home/cnb/.netrc` |
| Auth bypass | N/A | `GONOSUMDB=*` (skip checksum DB verification) |
| Secret keys | `pkg-python-url`, `pkg-python-username`, `pkg-python-password` | `pkg-go-url`, `pkg-go-username`, `pkg-go-password` |
| Variable accumulated | `_LANG_ENV` | `_LANG_ENV` + `_LANG_VOLUMES` (for .netrc) |
| Detection file | `requirements.txt` | `go.mod` |

## Test results

### 0.1.0 (2026-03-09)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — `GOPROXY=https://proxy.golang.org\|direct` used (default), Go SDK downloaded from `dl.google.com/go/go1.25.8.linux-amd64.tar.gz`, build succeeded |
| 2a | Proxy (fake URL, no auth) | PASSED — `GOPROXY=https://your-proxy/repository/go-proxy/,direct` picked up, `go mod download` attempted fetch from fake URL, failed with DNS `no such host` (expected) |
| 2b | Proxy (real Nexus, no auth) | PASSED — `GOPROXY=https://...ngrok-free.app/repository/go-proxy/,direct`, `go mod download` succeeded (3.07s), `go-chi/chi` fetched through Nexus, build succeeded |
| 3a | Proxy + auth (fake URL) | PASSED — `.netrc` generated, `GONOSUMDB=*` set, `_LANG_VOLUMES` has `.netrc` mount, DNS `no such host` (expected with fake URL) |
| 3b | Proxy + auth (real Nexus) | PASSED — `.netrc` mounted at `/home/cnb/.netrc`, `GONOSUMDB=*` set, `go mod download` succeeded (1.41s) through authenticated Nexus, build succeeded |
