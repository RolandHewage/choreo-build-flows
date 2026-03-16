# Prism Mock Proxy E2E Test

E2E test image that runs a real `podman build` for a Prism mock service, validating the
custom registry proxy CICD pipeline for OCI image resolution and npm proxy.

## What it tests

The Prism proxy flow from `prism-build.ts` + `workflow-resources.ts`:
- OCI image resolution via `_resolve_image` with strategy `"prism"` (ACR mirror rewrite)
- Two managed images: Prism server (`stoplight/prism:5`) + Golang (`golang:1.22.4-alpine`)
- Mirror key: `oci-choreo-url` (not `oci-buildpacks-url`)
- Registry login via `_proxy_login prism`
- npm proxy via `_setup_npm_proxy prism` — configures npm registry for build-time `npm install`
- `podman build` with resolved images (simulating prism-docker-resource-generator output)

Sample app: Petstore OpenAPI spec (based on `wso2/choreo-samples/prism-mock-service`).

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/prism-proxy-e2e:0.1.0 .
docker push rolandhewage/prism-proxy-e2e:0.1.0
```

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-choreo-url` | Choreo ACR mirror host | Yes |
| `oci-choreo-username` | Choreo ACR mirror username | Yes |
| `oci-choreo-password` | Choreo ACR mirror password | Yes |
| `pkg-npm-url` | npm registry proxy URL | Scenarios 4 & 5 |
| `pkg-npm-token` | npm auth token | Scenario 5 |

---

## Test scenarios — 0.1.0 (K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-prism \
  --from-literal=oci-choreo-url=choreocontrolplane.azurecr.io \
  --from-literal=oci-choreo-username=<acr-username> \
  --from-literal=oci-choreo-password='<acr-password>'

# ACR + OCI mirror (scenario 2)
kubectl create secret generic test-proxy-config-prism-mirror \
  --from-literal=oci-choreo-url=my-mirror.example.com

# ACR + OCI mirror + auth (scenario 3)
kubectl create secret generic test-proxy-config-prism-auth \
  --from-literal=oci-choreo-url=my-mirror.example.com \
  --from-literal=oci-choreo-username=<mirror-username> \
  --from-literal=oci-choreo-password='<mirror-password>'

# ACR + npm proxy (scenario 4)
kubectl create secret generic test-proxy-config-prism-npm \
  --from-literal=oci-choreo-url=choreocontrolplane.azurecr.io \
  --from-literal=oci-choreo-username=<acr-username> \
  --from-literal=oci-choreo-password='<acr-password>' \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/

# ACR + npm proxy + auth (scenario 5)
kubectl create secret generic test-proxy-config-prism-npm-auth \
  --from-literal=oci-choreo-url=choreocontrolplane.azurecr.io \
  --from-literal=oci-choreo-username=<acr-username> \
  --from-literal=oci-choreo-password='<acr-password>' \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/ \
  --from-literal=pkg-npm-token='<npm-token>'
```

### 1. No-proxy (ACR only, default flow baseline)

```bash
kubectl run prism-test --rm -it --restart=Never \
  --image=rolandhewage/prism-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"prism-test","image":"rolandhewage/prism-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-prism","optional":true}}]}}'
```

**Expected:** Prism + Golang pulled from `choreocontrolplane.azurecr.io`, no npm proxy, prints `E2E TEST PASSED (prism)`.

### 2. Proxy (OCI mirror rewrite)

```bash
kubectl run prism-test --rm -it --restart=Never \
  --image=rolandhewage/prism-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"prism-test","image":"rolandhewage/prism-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-prism-mirror","optional":true}}]}}'
```

**Expected:** Resolved images show `my-mirror.example.com/...`. Image pull fails with fake URL (expected).

### 3. Proxy + auth (OCI mirror with credentials)

```bash
kubectl run prism-test --rm -it --restart=Never \
  --image=rolandhewage/prism-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"prism-test","image":"rolandhewage/prism-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-prism-auth","optional":true}}]}}'
```

**Expected:** `Logging into proxy mirror: my-mirror.example.com` shown, images resolved to mirror.

### 4. npm proxy (verify registry config)

```bash
kubectl run prism-test --rm -it --restart=Never \
  --image=rolandhewage/prism-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"prism-test","image":"rolandhewage/prism-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-prism-npm","optional":true}}]}}'
```

**Expected:** `npm registry: https://your-proxy/repository/npm-proxy/`, images from ACR, build succeeds.

### 5. npm proxy + auth (verify registry + token)

```bash
kubectl run prism-test --rm -it --restart=Never \
  --image=rolandhewage/prism-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"prism-test","image":"rolandhewage/prism-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-prism-npm-auth","optional":true}}]}}'
```

**Expected:** npm registry set with authToken, images from ACR, build succeeds.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-prism test-proxy-config-prism-mirror test-proxy-config-prism-auth test-proxy-config-prism-npm test-proxy-config-prism-npm-auth
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

1. **Enable npm Bearer Token Realm** in Nexus UI:
   `Settings → Realms → move "npm Bearer Token Realm" to Active → Save`

2. **Login to Nexus npm registry:**
   ```bash
   npm login --registry=http://localhost:8081/repository/npm-proxy/
   ```

3. **Copy the token** from `~/.npmrc`:
   ```bash
   grep '_authToken' ~/.npmrc
   ```
   ```
   //localhost:8081/repository/npm-proxy/:_authToken=eyJhbGciOiJIUzI1NiJ9...
   ```
   The value after `_authToken=` is the token to use as `pkg-npm-token` in the K8s Secret.

4. **Clean up after done** — remove the Nexus token from your local `.npmrc`:
   ```bash
   npm logout --registry=http://localhost:8081/repository/npm-proxy/
   ```

| K8s Secret key | Value |
|---|---|
| `pkg-npm-url` | Nexus npm proxy repo URL (e.g. `http://localhost:8081/repository/npm-proxy/`) |
| `pkg-npm-token` | npm auth token from `npm login` |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

---

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| npm registry configured | After `npm proxy setup` — shows configured registry URL |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Generated Dockerfile | After `Generate Dockerfile` — shows FROM lines with resolved images |
| Build completes | `E2E TEST PASSED` at the end |

## Test results

### 0.1.0 (2026-03-16)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — ACR login, images resolved, podman build succeeded |
| 2 | OCI mirror (fake URL) | PASSED — `_resolve_image` rewrote to `my-mirror.example.com/...`, DNS failed as expected |
| 3 | OCI mirror + auth | PASSED — `_proxy_login prism` attempted login, DNS failed as expected |
| 4 | npm proxy | PASSED — npm registry set to ngrok URL, proxy config validated |
| 5 | npm proxy + auth | PASSED — npm registry + token configured, proxy config validated |

E2E image: `rolandhewage/prism-proxy-e2e:0.1.0`

## Key difference from other tests

| Aspect | Buildpack (Go, Java, etc.) | Prism Mock |
|---|---|---|
| Strategy | `buildpack` | `prism` |
| Build tool | `pack build` (Cloud Native Buildpacks) | `podman build` (Dockerfile) |
| Managed images | Builder + Lifecycle + Run (via `oci-buildpacks-url`) | Prism + Golang (via `oci-choreo-url`) |
| Package proxy | Language-specific (Maven, npm, Go, etc.) | npm (for prism-docker-resource-generator) |
| Dockerfile | Not used (buildpack generates) | Generated by prism-docker-resource-generator |
