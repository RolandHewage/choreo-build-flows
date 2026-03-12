# Ballerina OCI Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Ballerina app, validating the
custom registry proxy CICD pipeline for OCI image resolution.

## What it tests

The Ballerina proxy flow from `ballerina-build.ts`:
- OCI image resolution via `_resolve_image` with strategy `"ballerina"` (ACR mirror rewrite)
- Explicit lifecycle image via `pack config lifecycle-image` (unique to Ballerina)
- Registry login via `_proxy_login ballerina`
- No package manager proxy (Ballerina Central is not proxied)

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/ballerina-proxy-e2e:0.1.0 .
docker push rolandhewage/ballerina-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Choreo Ballerina buildpack runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed. No package proxy keys (OCI only).

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-ballerina \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + OCI mirror (scenario 2)
kubectl create secret generic test-proxy-config-ballerina-mirror \
  --from-literal=oci-buildpacks-url=my-mirror.example.com

# ACR + OCI mirror + auth (scenario 3)
kubectl create secret generic test-proxy-config-ballerina-auth \
  --from-literal=oci-buildpacks-url=my-mirror.example.com \
  --from-literal=oci-buildpacks-username=<mirror-username> \
  --from-literal=oci-buildpacks-password='<mirror-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no mirror rewrite).

```bash
kubectl run ballerina-test --rm -it --restart=Never \
  --image=rolandhewage/ballerina-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"ballerina-test",
        "image":"rolandhewage/ballerina-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-ballerina","optional":true}}]
    }
  }'
```

**Expected:** Lifecycle + builder pulled from `choreoprivateacr.azurecr.io`, `pack config lifecycle-image` set, build succeeds, prints `E2E TEST PASSED (ballerina)`.

### 2. Proxy (OCI mirror rewrite)

Verifies `_resolve_image` rewrites both lifecycle and builder image refs via `oci-buildpacks-url`.

```bash
kubectl run ballerina-test --rm -it --restart=Never \
  --image=rolandhewage/ballerina-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"ballerina-test",
        "image":"rolandhewage/ballerina-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-ballerina-mirror","optional":true}}]
    }
  }'
```

**Expected:** Resolved images show `my-mirror.example.com/...` instead of `choreoprivateacr.azurecr.io/...`. With a fake mirror, image pull fails (expected).

### 3. Proxy + auth (OCI mirror with credentials)

Verifies `_proxy_login ballerina` logs into the mirror registry before image resolution.

```bash
kubectl run ballerina-test --rm -it --restart=Never \
  --image=rolandhewage/ballerina-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"ballerina-test",
        "image":"rolandhewage/ballerina-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-ballerina-auth","optional":true}}]
    }
  }'
```

**Expected:** `Logging into proxy mirror: my-mirror.example.com` shown, images resolved to mirror. With a real mirror, build succeeds.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-ballerina test-proxy-config-ballerina-mirror test-proxy-config-ballerina-auth
```

---

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| Lifecycle image configured | After `pack config lifecycle-image` — shows resolved lifecycle image |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from other tests

| Aspect | Go/Java/etc. (buildpack) | Ballerina |
|---|---|---|
| Strategy | `buildpack` | `ballerina` |
| Builder | Google builder (public, mirrored on ACR) | Choreo custom builder (private ACR only) |
| Lifecycle | Builder default (implicit) | Explicit via `pack config lifecycle-image` |
| Package proxy | Yes (`GOPROXY`, `PIP_INDEX_URL`, Maven `settings.xml`, etc.) | No (Ballerina Central not proxied) |
| Secret keys | `oci-buildpacks-*` + `pkg-<lang>-*` | `oci-buildpacks-*` only |

## Test results

### 0.1.0 (2026-03-12)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — `_resolve_image` rewrote to `choreocontrolplane.azurecr.io/...`, ACR login succeeded, Ballerina 2201.13.1 compiled with deps from `dev-central.ballerina.io`, image built successfully |
| 2 | Proxy (OCI mirror) | PASSED — `_resolve_image` rewrote to `my-mirror.example.com/...`, `_proxy_login` skipped (no credentials, correct), image pull failed with `no such host` (expected with fake URL) |
| 3 | Proxy + auth | PASSED — `_proxy_login ballerina` attempted login to `my-mirror.example.com` with credentials, failed with `no such host` (expected with fake URL) |
