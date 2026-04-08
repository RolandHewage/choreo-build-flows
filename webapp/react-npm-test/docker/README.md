# React NPM Webapp Proxy E2E Test — Podman Build Flow

E2E test image that runs a real `podman build` for a React webapp, validating the
custom registry proxy CICD pipeline for webapp/npm.

## What it tests

The webapp proxy flow from `webapp-build.ts` (lines 67-84):
- `_resolve_image` for `node` and `nginx` base images (DockerHub/Choreo mirrors)
- Conditional `--build-arg` flags only when values differ from defaults
- `--build-arg NPM_REGISTRY=$_NPM_URL` for npm registry override
- `.npmrc` generation with `_authToken` and `--secret id=npmrc` for token auth
- `_proxy_login webapp` for mirror authentication
- OCI image resolution via `_resolve_image` (DockerHub/Choreo mirror rewrite)

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/webapp-npm-proxy-e2e:0.1.0 .
docker push rolandhewage/webapp-npm-proxy-e2e:0.1.0
```

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-dockerhub-url` | DockerHub mirror host (for node image) | Optional |
| `oci-dockerhub-username` | DockerHub mirror username | Optional |
| `oci-dockerhub-password` | DockerHub mirror password | Optional |
| `oci-choreo-url` | Choreo ACR mirror host (for nginx image) | Optional |
| `oci-choreo-username` | Choreo ACR mirror username | Optional |
| `oci-choreo-password` | Choreo ACR mirror password | Optional |
| `pkg-npm-url` | npm registry proxy URL (e.g. `https://nexus/repository/npm-proxy/`) | Scenarios 2 & 3 |
| `pkg-npm-token` | npm registry auth token | Scenario 3 |

### Restricted / air-gapped clusters

On clusters where Docker Hub and/or Choreo ACR are blocked, the `podman build` will fail pulling
base images (`node:18-alpine` from Docker Hub, `nginx-unprivileged` from Choreo ACR) even if the
npm proxy is configured correctly. In this case, the OCI mirror keys above become **required**:

```bash
kubectl create secret generic choreo-build-registry-proxy \
  --from-literal=oci-dockerhub-url=your-mirror.example.com/docker-hub-proxy \
  --from-literal=oci-dockerhub-username=<username> \
  --from-literal=oci-dockerhub-password='<password>' \
  --from-literal=oci-choreo-url=your-mirror.example.com/choreo-acr-proxy \
  --from-literal=oci-choreo-username=<username> \
  --from-literal=oci-choreo-password='<password>' \
  --from-literal=pkg-npm-url=https://your-mirror.example.com/repository/npm-proxy/ \
  --from-literal=pkg-npm-token=<token>
```

This rewrites `node:18-alpine` → `your-mirror/docker-hub-proxy/library/node:18-alpine` and
`choreoanonymouspullable.azurecr.io/nginxinc/...` → `your-mirror/choreo-acr-proxy/nginxinc/...`,
allowing the build to pull all images from the internal mirror.

**Important:**
- `oci-dockerhub-url` **must** include `library/` — Docker Hub official images (like `node`) are under the `library/` namespace. Nexus Docker proxy does not add this implicitly. Example: `oci-dockerhub-url=nexusrepo.example.com/docker-proxy/library`
- `oci-choreo-url` must **NOT** include `library/` — the nginx image (`nginxinc/nginx-unprivileged`) is an org image, not an official image. It already has its namespace. Example: `oci-choreo-url=nexusrepo.example.com/docker-proxy`

---

## Test scenarios — 0.1.0 (K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.
>
> **Important:** Run scenarios in order (1 → 2 → 3). Nexus caches packages
> after the first authenticated fetch. If scenario 3 runs before 2, cached
> packages may cause scenario 2 to falsely pass even when anonymous access
> is disabled. To re-test scenario 2 after 3, delete and recreate the
> Nexus `npm-proxy` repository to clear the blob store.

### Prerequisite — create secrets

```bash
# No-proxy (scenario 1) — empty secret or no secret
kubectl create secret generic test-proxy-config-npm \
  --from-literal=placeholder=true

# NPM proxy without auth (scenario 2)
kubectl create secret generic test-proxy-config-npm-anon \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/

# NPM proxy with token auth (scenario 3)
kubectl create secret generic test-proxy-config-npm-auth \
  --from-literal=pkg-npm-url=https://your-proxy/repository/npm-proxy/ \
  --from-literal=pkg-npm-token=your-npm-token
```

### 1. No-proxy (default flow baseline)

Verifies builds work when no proxy config is mounted (default node/nginx images, npmjs.org registry).

```bash
kubectl run webapp-test --rm -it --restart=Never \
  --image=rolandhewage/webapp-npm-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"webapp-test",
        "image":"rolandhewage/webapp-npm-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm","optional":true}}]
    }
  }'
```

**Expected:** `npm install` fetches from registry.npmjs.org, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2. Proxy without auth

Verifies `--build-arg NPM_REGISTRY` is passed to `podman build` and npm uses the proxy URL.

```bash
kubectl run webapp-test --rm -it --restart=Never \
  --image=rolandhewage/webapp-npm-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"webapp-test",
        "image":"rolandhewage/webapp-npm-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm-anon","optional":true}}]
    }
  }'
```

**Expected:** `--build-arg NPM_REGISTRY=<url>` in podman build command. With a fake URL, npm fails. With a real proxy, build succeeds.

### 3. Proxy with token auth

Verifies `.npmrc` is generated with `_authToken` and passed as `--secret id=npmrc`.

```bash
kubectl run webapp-test --rm -it --restart=Never \
  --image=rolandhewage/webapp-npm-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"webapp-test",
        "image":"rolandhewage/webapp-npm-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-npm-auth","optional":true}}]
    }
  }'
```

**Expected:** `Generated /tmp/.npmrc for host: <host>`, `--secret id=npmrc,src=/tmp/.npmrc` in build command.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-npm test-proxy-config-npm-anon test-proxy-config-npm-auth
```

---

## Obtaining npm token from Nexus

1. **Enable npm Bearer Token Realm** in Nexus UI:
   `Settings → Realms → move "npm Bearer Token Realm" to Active → Save`

2. **Login to Nexus npm registry:**
   ```bash
   npm login --registry=http://localhost:8081/repository/npm-proxy/
   ```
   Enter Nexus username, password, and email.

3. **Copy the token** from `~/.npmrc`:
   ```bash
   cat ~/.npmrc
   ```
   ```
   //localhost:8081/repository/npm-proxy/:_authToken=eyJhbGciOiJIUzI1NiJ9...
   ```
   The value after `_authToken=` is the token to use as `pkg-npm-token` in the K8s Secret.

> **Note:** Tokens are mainly required for `npm-hosted` (publishing private packages). For `npm-proxy` repositories, anonymous read access usually works without a token (as confirmed in scenario 2b).

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

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images` — `_NODE_IMAGE` and `_NGINX_IMAGE` values |
| Build-args conditional | `_BUILD_ARGS` should only have overrides when values differ from defaults |
| NPM registry override | `--build-arg NPM_REGISTRY=<url>` in build command |
| `.npmrc` generated (auth) | After `Generated /tmp/.npmrc for host:` |
| `--secret id=npmrc` in command | In the full `podman build` command line |
| `npm install` uses proxy | During build phase — should show proxy URL, NOT registry.npmjs.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from buildpack flow

| Aspect | Buildpack (pip/NuGet) | Webapp (npm) |
|---|---|---|
| Build tool | `pack build` | `podman build` (Dockerfile) |
| Registry override | `--env PIP_INDEX_URL` / NuGet.Config volume | `--build-arg NPM_REGISTRY` |
| Auth mechanism | URL-embedded credentials / XML credentials | `--secret id=npmrc` (Docker build secret) |
| Image resolution | Builder/lifecycle/run images | Node/nginx base images |
| Detection file | `requirements.txt` / `.csproj` | `package.json` |

## Test results

### 0.1.0 (2026-03-04)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PASSED |
| 2a | Proxy without auth (fake URL) | PASSED (expected `ENOTFOUND` failure confirms proxy redirect) |
| 2b | Proxy without auth (real Nexus via ngrok) | PASSED |
| 3 | Proxy with token auth (real Nexus via ngrok) | PASSED |

### 0.1.0 — with Docker Hub mirror (2026-04-07)

Tested with `oci-dockerhub-url` pointing to Nexus Docker Hub proxy with `library/` path.

| # | Scenario | Result |
|---|---|---|
| 1 | Proxy with auth + Docker Hub mirror | PASSED — node:18-alpine pulled from ngrok Nexus Docker proxy (`docker-hub-proxy/library/node:18-alpine`), nginx from `choreoanonymouspullable.azurecr.io`, npm packages through ngrok Nexus npm proxy |

**Key finding:** `oci-dockerhub-url` must include `library/` suffix for Nexus Docker proxy (e.g., `nexusrepo.example.com/docker-hub-proxy/library`).

#### Bugs found during Angular/Vue testing (also apply to React)

1. **`npm install -g pnpm` ordering** — ran after `npm config set registry`, causing pnpm install to fail (E401) when proxy requires auth. Fixed: moved before registry override.
2. **`.npmrc` secret not mounted in Dockerfile** — `--secret id=npmrc` was passed to `podman build` but the Dockerfile never used `--mount=type=secret,id=npmrc,target=/root/.npmrc`. Token was never available during `npm install`. Fixed: added `--mount=type=secret` to the `npm install` RUN step. Both bugs also existed in the production CICD code (`web-apps.service.ts` and `webapp-build.ts`) and were fixed there too.
