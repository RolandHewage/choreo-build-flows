# Test Runner Proxy E2E Test

E2E test image that runs a real `podman build` for a Postman test runner, validating the
custom registry proxy CICD pipeline for OCI image resolution and npm proxy.

## What it tests

The test runner proxy flow from `test-runner-build.ts` + `workflow-resources.ts`:
- OCI image resolution via `_resolve_image` with strategy `"test-runner"`
- One managed image: Node.js (`node:18-alpine`) from Docker Hub
- Mirror key: `oci-dockerhub-url` (not `oci-choreo-url` or `oci-buildpacks-url`)
- Registry login via `_proxy_login test-runner`
- npm proxy via `--build-arg NPM_REGISTRY` + `--secret id=npmrc` for auth
- `podman build` with resolved Node image

Sample app: Postman collection (based on `wso2/choreo-samples/test-runner-postman`).
Dockerfile matches generated output from `test-runner.service.ts`.

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/test-runner-proxy-e2e:0.1.0 .
docker push rolandhewage/test-runner-proxy-e2e:0.1.0
```

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-dockerhub-url` | Docker Hub mirror host (for Node image) | Scenarios 2 & 3 |
| `oci-dockerhub-username` | Docker Hub mirror username | Scenario 3 |
| `oci-dockerhub-password` | Docker Hub mirror password | Scenario 3 |
| `pkg-npm-url` | npm registry proxy URL | Scenarios 4 & 5 |
| `pkg-npm-token` | npm auth token | Scenario 5 |

---

## Test scenarios — 0.1.0 (K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# No-proxy (scenario 1) — no secret needed, Docker Hub is public

# OCI mirror (scenario 2)
kubectl create secret generic test-proxy-config-tr-mirror \
  --from-literal=oci-dockerhub-url=my-mirror.example.com

# OCI mirror + auth (scenario 3)
kubectl create secret generic test-proxy-config-tr-auth \
  --from-literal=oci-dockerhub-url=my-mirror.example.com \
  --from-literal=oci-dockerhub-username=<mirror-username> \
  --from-literal=oci-dockerhub-password='<mirror-password>'

# npm proxy (scenario 4)
kubectl create secret generic test-proxy-config-tr-npm \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/

# npm proxy + auth (scenario 5)
kubectl create secret generic test-proxy-config-tr-npm-auth \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/ \
  --from-literal=pkg-npm-token='<npm-token>'
```

### 1. No-proxy (Docker Hub, default flow baseline)

```bash
kubectl run tr-test --rm -it --restart=Never \
  --image=rolandhewage/test-runner-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"tr-test","image":"rolandhewage/test-runner-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true}}]}}'
```

**Expected:** Node.js pulled from Docker Hub, newman installed from registry.npmjs.org, prints `E2E TEST PASSED (test-runner)`.

### 2. Proxy (OCI mirror rewrite)

```bash
kubectl run tr-test --rm -it --restart=Never \
  --image=rolandhewage/test-runner-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"tr-test","image":"rolandhewage/test-runner-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-tr-mirror","optional":true}}]}}'
```

**Expected:** Resolved image shows `my-mirror.example.com/node:18-alpine`. Image pull fails with fake URL (expected).

### 3. Proxy + auth (OCI mirror with credentials)

```bash
kubectl run tr-test --rm -it --restart=Never \
  --image=rolandhewage/test-runner-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"tr-test","image":"rolandhewage/test-runner-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-tr-auth","optional":true}}]}}'
```

**Expected:** `Logging into proxy mirror: my-mirror.example.com` shown, images resolved to mirror.

### 4. npm proxy (verify build arg)

```bash
kubectl run tr-test --rm -it --restart=Never \
  --image=rolandhewage/test-runner-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"tr-test","image":"rolandhewage/test-runner-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-tr-npm","optional":true}}]}}'
```

**Expected:** `--build-arg NPM_REGISTRY=<url>` in podman build command. With a fake URL, npm install fails. With a real proxy, build succeeds.

### 5. npm proxy + auth (verify .npmrc secret)

```bash
kubectl run tr-test --rm -it --restart=Never \
  --image=rolandhewage/test-runner-proxy-e2e:0.1.0 \
  --overrides='{"spec":{"containers":[{"name":"tr-test","image":"rolandhewage/test-runner-proxy-e2e:0.1.0","imagePullPolicy":"Always","securityContext":{"privileged":true},"volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]}],"volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-tr-npm-auth","optional":true}}]}}'
```

**Expected:** `Generated /tmp/.npmrc for host: <host>`, `--secret id=npmrc,src=/tmp/.npmrc` in build command.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-tr-mirror test-proxy-config-tr-auth test-proxy-config-tr-npm test-proxy-config-tr-npm-auth
```

---

## Testing with local Nexus via ngrok

### Nexus setup for Docker Hub proxy (OCI mirror)

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **docker (proxy)**
2. **Name:** `docker-hub-proxy`, **Remote storage:** `https://registry-1.docker.io`
3. **Docker Registry API Support:** Check **Enable Docker V1 API**
4. **Anonymous access:** Check **Allow anonymous Docker pulls** (requires Global Anonymous Access + Docker Bearer Token Realm)
5. **HTTP connector:** Set port `8082`
6. Enable realm: **Settings** → **Security** → **Realms** → move **Docker Bearer Token Realm** to Active → Save

```bash
# Start ngrok tunnel to Nexus Docker proxy
ngrok http 8082

# Use the ngrok host in the K8s Secret as oci-dockerhub-url
# e.g., abc123.ngrok-free.app
```

| K8s Secret key | Value |
|---|---|
| `oci-dockerhub-url` | ngrok host (e.g. `abc123.ngrok-free.app`) |
| `oci-dockerhub-username` | Nexus username (e.g. `admin`) |
| `oci-dockerhub-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

### Nexus setup for npm proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **npm (proxy)**
2. **Name:** `npm-proxy`, **Remote storage:** `https://registry.npmjs.org`
3. Repository URL: `http://localhost:8081/repository/npm-proxy/`

```bash
# Start ngrok tunnel to Nexus npm proxy
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-npm-url
# e.g., https://abc123.ngrok-free.app/repository/npm-proxy/
```

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
| Node image resolved | After `Resolve images via _resolve_image` — `node:18-alpine` → resolved to mirror |
| npm proxy URL set | After `npm proxy setup` — `_NPM_URL` shows proxy URL |
| `.npmrc` generated (auth) | After `Generated /tmp/.npmrc for host:` |
| `--build-arg NPM_REGISTRY` | In the full `podman build` command line |
| `--secret id=npmrc` | In the full `podman build` command line (auth scenario) |
| newman installed | During build — `npm i -g newman` output |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from other tests

| Aspect | Webapp (React, etc.) | Test Runner |
|---|---|---|
| Strategy | `webapp` | `test-runner` |
| Build tool | `podman build` | `podman build` |
| Managed images | Node + Nginx (via `oci-dockerhub-url` + `oci-choreo-url`) | Node only (via `oci-dockerhub-url`) |
| Package proxy | npm (`--build-arg` + `--secret`) | npm (`--build-arg` + `--secret`) |
| Dockerfile source | Template in `web-apps.service.ts` | Generated by `test-runner.service.ts` |
| npm usage | App dependencies (`npm install`) | Newman CLI (`npm i -g newman`) |

---

## Test results

### 0.1.0 (2026-03-16)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (Docker Hub) | PASSED — Node pulled from Docker Hub, newman installed, `E2E TEST PASSED (test-runner)` |
| 2 | OCI mirror (fake URL) | PASSED — `_resolve_image` rewrote to `my-mirror.example.com/node:18-alpine`, DNS failed as expected |
| 3a | OCI mirror + auth (fake URL) | PASSED — `_proxy_login test-runner` attempted login to `my-mirror.example.com`, DNS failed as expected |
| 3b | OCI mirror + auth (Nexus) | PASSED — `Login Succeeded!`, image resolved to ngrok Docker Hub mirror |
| 4 | npm proxy | PASSED — `--build-arg NPM_REGISTRY=<url>` in build command, proxy config validated |
| 5 | npm proxy + auth | PASSED — `.npmrc` generated, `--secret id=npmrc,src=/tmp/.npmrc` in build command, proxy config validated |

E2E image: `rolandhewage/test-runner-proxy-e2e:0.1.0`
