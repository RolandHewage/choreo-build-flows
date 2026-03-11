# Node.js npm Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Node.js app, validating the
custom registry proxy CICD pipeline for npm dependencies.

## What it tests

The npm proxy flow from `buildpack-build.ts`:
- `NPM_CONFIG_REGISTRY` env var passed to `pack build` via `--env`
- `.npmrc` auth: `pkg-npm-token` → `.npmrc` file with `_authToken` mounted at `/home/cnb/.npmrc`
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/npm-bp-proxy-e2e:0.1.0 .
docker push rolandhewage/npm-bp-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Node.js runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-npm-url` | npm registry proxy URL (e.g. `https://nexus/repository/npm-proxy/`) | Scenarios 2 & 3 |
| `pkg-npm-token` | npm auth token (for authenticated proxies) | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-npm-bp \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + npm proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-npm-bp-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/

# ACR + npm proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-npm-bp-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/ \
  --from-literal=pkg-npm-token='<npm-auth-token>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no npm proxy config).

```bash
kubectl run npm-bp-test --rm -it --restart=Never \
  --image=rolandhewage/npm-bp-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"npm-bp-test",
        "image":"rolandhewage/npm-bp-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm-bp","optional":true}}]
    }
  }'
```

**Expected:** `npm install` fetches from `registry.npmjs.org`, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify NPM_CONFIG_REGISTRY is picked up)

Verifies `NPM_CONFIG_REGISTRY` is passed as env var to `pack build`.

```bash
kubectl run npm-bp-test --rm -it --restart=Never \
  --image=rolandhewage/npm-bp-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"npm-bp-test",
        "image":"rolandhewage/npm-bp-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm-bp-proxy","optional":true}}]
    }
  }'
```

**Expected:** `_LANG_ENV` shows `--env NPM_CONFIG_REGISTRY=<url>`. With a fake URL, `npm install` fails. With a real proxy, build succeeds.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus npm proxy URL in the secret.

**Expected:** npm packages (`express`) fetched through Nexus npm proxy.

### 3a. Proxy with auth — fake URL (verify .npmrc generation)

Verifies `.npmrc` file is generated with `_authToken` and mounted.

```bash
kubectl run npm-bp-test --rm -it --restart=Never \
  --image=rolandhewage/npm-bp-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"npm-bp-test",
        "image":"rolandhewage/npm-bp-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm-bp-auth","optional":true}}]
    }
  }'
```

**Expected:** `_LANG_VOLUMES` includes `--volume /tmp/npm-proxy-auth/.npmrc:/home/cnb/.npmrc`, `.npmrc` shows `//host/:_authToken=****`. With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus npm proxy URL and token in the secret.

**Expected:** `.npmrc` used for authentication, npm packages fetched through authenticated Nexus npm proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-npm-bp test-proxy-config-npm-bp-proxy test-proxy-config-npm-bp-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-npm-url
# e.g., https://abc123.ngrok-free.app/repository/npm-proxy/
```

### Nexus setup for npm proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **npm (proxy)**
2. **Name:** `npm-proxy`, **Remote storage:** `https://registry.npmjs.org`
3. Repository URL: `http://localhost:8081/repository/npm-proxy/`

### Obtaining npm token from Nexus

```bash
# npm login against Nexus to get a bearer token
npm login --registry=http://localhost:8081/repository/npm-proxy/
# Token is saved in ~/.npmrc — extract it
grep '_authToken' ~/.npmrc

# Clean up after done — remove the Nexus token from your local .npmrc
npm logout --registry=http://localhost:8081/repository/npm-proxy/
```

| K8s Secret key | Value |
|---|---|
| `pkg-npm-url` | Nexus npm proxy repo URL (e.g. `http://localhost:8081/repository/npm-proxy/`) |
| `pkg-npm-token` | npm auth token from `npm login` |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD generates a `.npmrc` file with `//host/:_authToken=<token>` and mounts it at `/home/cnb/.npmrc`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `NPM_CONFIG_REGISTRY` set | `_LANG_ENV` line shows `--env NPM_CONFIG_REGISTRY=...` |
| `.npmrc` generated (auth) | `_LANG_VOLUMES` line shows `--volume /tmp/npm-proxy-auth/.npmrc:/home/cnb/.npmrc` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| `npm install` uses proxy | During BUILDING phase — should show proxy URL, NOT registry.npmjs.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from webapp npm test

| Aspect | Webapp npm | Buildpack npm |
|---|---|---|
| Build tool | `podman build` (Dockerfile) | `pack build` (Google buildpacks) |
| Proxy mechanism | `.npmrc` via `--secret id=npmrc` in podman build | `NPM_CONFIG_REGISTRY` env var + `.npmrc` mounted at `/home/cnb/.npmrc` |
| Auth secret key | `pkg-npm-token` | `pkg-npm-token` |
| Auth method | `.npmrc` with `_authToken` (build secret) | `.npmrc` with `_authToken` (volume mount) |
| Secret keys | `pkg-npm-url`, `pkg-npm-token` | `pkg-npm-url`, `pkg-npm-token` |
| Variable accumulated | `_BUILD_ARGS` | `_LANG_ENV` + `_LANG_VOLUMES` (for .npmrc) |
| Detection file | `package.json` | `package.json` |

## Test results

### 0.1.0

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — Node.js v22.22.0 from `dl.google.com`, npm packages from registry.npmjs.org, build succeeded |
| 2a | Proxy (fake URL, no auth) | PASSED — `NPM_CONFIG_REGISTRY` set, npm tried `https://your-proxy/repository/npm-proxy/express`, `ENOTFOUND` as expected, default registry bypassed |
| 2b | Proxy (real Nexus, no auth) | PASSED — npm packages fetched through ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), build succeeded |
| 3a | Proxy + auth (fake URL) | PASSED — `.npmrc` with `_authToken` generated and volume-mounted, npm tried `https://your-proxy/repository/npm-proxy/express`, `ENOTFOUND` as expected |
| 3b | Proxy + auth (real Nexus) | PASSED — `.npmrc` with `_authToken` generated, volume-mounted at `/home/cnb/.npmrc`, npm packages fetched through authenticated ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), build succeeded |
