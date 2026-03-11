# Static Files Webapp Proxy E2E Test — Podman Build Flow

E2E test image that runs a real `podman build` for a static files webapp, validating the
custom registry proxy CICD pipeline for webapp/static-files.

## What it tests

The webapp proxy flow from `webapp-build.ts` (lines 67-84), static files subset:
- `_resolve_image` for `nginx` base image (Choreo ACR mirror)
- Conditional `--build-arg NGINX_IMAGE` only when value differs from default
- `_proxy_login webapp` for mirror authentication

**Note:** Static files don't use Node.js or npm. The Dockerfile only has `ARG NGINX_IMAGE` —
no `NODE_IMAGE`, no `NPM_REGISTRY`, no `.npmrc`. However, `webapp-build.ts` uses the same
script for all webapp types, so node/npm args are resolved but harmlessly ignored by the
static files Dockerfile.

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/webapp-static-proxy-e2e:0.1.0 .
docker push rolandhewage/webapp-static-proxy-e2e:0.1.0
```

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-choreo-url` | Choreo ACR mirror host (for nginx image) | Scenario 2 |
| `oci-choreo-username` | Choreo ACR mirror username | Scenario 2 |
| `oci-choreo-password` | Choreo ACR mirror password | Scenario 2 |

---

## Test scenarios — 0.1.0 (K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# No-proxy (scenario 1) — empty secret or no secret
kubectl create secret generic test-proxy-config-static \
  --from-literal=placeholder=true

# Choreo ACR mirror (scenario 2)
kubectl create secret generic test-proxy-config-static-mirror \
  --from-literal=oci-choreo-url=your-mirror-registry.example.com \
  --from-literal=oci-choreo-username=<username> \
  --from-literal=oci-choreo-password='<password>'
```

### 1. No-proxy (default flow baseline)

Verifies builds work when no proxy config is mounted (default nginx image from Choreo ACR).

```bash
kubectl run static-test --rm -it --restart=Never \
  --image=rolandhewage/webapp-static-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"static-test",
        "image":"rolandhewage/webapp-static-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-static","optional":true}}]
    }
  }'
```

**Expected:** Default nginx image pulled from `choreoanonymouspullable.azurecr.io`, build succeeds, prints `E2E TEST PASSED (static files)`.

### 2. Choreo ACR mirror (nginx image resolved via proxy)

Verifies `--build-arg NGINX_IMAGE` is passed when `oci-choreo-url` resolves to a different mirror.

```bash
kubectl run static-test --rm -it --restart=Never \
  --image=rolandhewage/webapp-static-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"static-test",
        "image":"rolandhewage/webapp-static-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-static-mirror","optional":true}}]
    }
  }'
```

**Expected:** `--build-arg NGINX_IMAGE=<mirror>/nginxinc/nginx-unprivileged:stable-alpine-slim` in build command. nginx pulled from mirror registry.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-static test-proxy-config-static-mirror
```

---

## Key difference from React/Angular/Vue tests

| Aspect | React/Angular/Vue | Static Files |
|---|---|---|
| Node.js | Yes (`ARG NODE_IMAGE`) | No |
| npm install | Yes (`ARG NPM_REGISTRY`, `.npmrc`) | No |
| nginx | Yes (`ARG NGINX_IMAGE`) | Yes (`ARG NGINX_IMAGE`) |
| Proxy touchpoints | node image + nginx image + npm registry | nginx image only |

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Nginx image resolved | After `Resolve images` — `_NGINX_IMAGE` value |
| Node/npm noted as unused | `(unused for static files)` labels |
| Build-args conditional | `_BUILD_ARGS` should only have `NGINX_IMAGE` override when mirror differs |
| Build completes | `E2E TEST PASSED (static files)` at the end |

## Test results

### 0.1.0 (2026-03-11)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (default flow) | PASSED |
| 2 | Choreo ACR mirror (`docker.io`) | PASSED — nginx pulled from Docker Hub instead of Choreo ACR |

**Testing note:** For scenario 2, `docker.io` can be used as `oci-choreo-url` since the nginx
image `nginxinc/nginx-unprivileged:stable-alpine-slim` exists on Docker Hub (it's the upstream
source that Choreo ACR mirrors from). No credentials needed — Docker Hub allows anonymous pulls.

E2E image: `rolandhewage/webapp-static-proxy-e2e:0.1.0`
