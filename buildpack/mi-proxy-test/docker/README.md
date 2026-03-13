# MI (Micro Integrator) Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for an MI app, validating the
custom registry proxy CICD pipeline for OCI image resolution and Maven dependencies.

## What it tests

The MI proxy flow from `mi-build-preparation.ts` + `workflow-resources.ts`:
- OCI image resolution via `_resolve_image` with strategy `"mi"` (ACR mirror rewrite)
- Explicit lifecycle image via `pack config lifecycle-image` (same as Ballerina)
- Registry login via `_proxy_login mi`
- Maven proxy via `_setup_maven_proxy mi` — generates `settings.xml` with `<mirror>` redirecting `*` to proxy URL
- Optional `<servers>` section with username/password for authenticated Maven proxies
- `settings.xml` mounted as Paketo buildpack binding at `/platform/bindings/maven-settings` via `_MAVEN_BINDING`
- `type` file written with value `maven` (required by Paketo binding spec)
- Maven cache volume at `/m2/repository`

The sample app is a proper WSO2 MI project (based on `wso2/choreo-samples/hello-world-mi`)
with multi-module Maven structure, synapse API config, and `carbon/application` CompositeExporter.

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/mi-proxy-e2e:0.1.0 .
docker push rolandhewage/mi-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Choreo MI buildpack runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-maven-url` | Maven proxy URL (e.g. `https://nexus/repository/maven-proxy/`) | Scenarios 4 & 5 |
| `pkg-maven-username` | Maven proxy username | Scenario 5 |
| `pkg-maven-password` | Maven proxy password | Scenario 5 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-mi \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + OCI mirror (scenario 2)
kubectl create secret generic test-proxy-config-mi-mirror \
  --from-literal=oci-buildpacks-url=my-mirror.example.com

# ACR + OCI mirror + auth (scenario 3)
kubectl create secret generic test-proxy-config-mi-auth \
  --from-literal=oci-buildpacks-url=my-mirror.example.com \
  --from-literal=oci-buildpacks-username=<mirror-username> \
  --from-literal=oci-buildpacks-password='<mirror-password>'

# ACR + Maven proxy, no auth (scenario 4)
kubectl create secret generic test-proxy-config-mi-maven \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-maven-url=https://your-proxy/repository/maven-proxy/

# ACR + Maven proxy + auth (scenario 5)
kubectl create secret generic test-proxy-config-mi-maven-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-maven-url=https://your-proxy/repository/maven-proxy/ \
  --from-literal=pkg-maven-username=<nexus-username> \
  --from-literal=pkg-maven-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no mirror rewrite, no Maven proxy).

```bash
kubectl run mi-test --rm -it --restart=Never \
  --image=rolandhewage/mi-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"mi-test",
        "image":"rolandhewage/mi-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-mi","optional":true}}]
    }
  }'
```

**Expected:** Lifecycle + builder pulled from `choreoprivateacr.azurecr.io`, no Maven proxy, `pack config lifecycle-image` set, prints `E2E TEST PASSED (mi)`.

### 2. Proxy (OCI mirror rewrite)

Verifies `_resolve_image` rewrites both lifecycle and builder image refs via `oci-buildpacks-url`.

```bash
kubectl run mi-test --rm -it --restart=Never \
  --image=rolandhewage/mi-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"mi-test",
        "image":"rolandhewage/mi-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-mi-mirror","optional":true}}]
    }
  }'
```

**Expected:** Resolved images show `my-mirror.example.com/...` instead of `choreoprivateacr.azurecr.io/...`. With a fake mirror, image pull fails (expected).

### 3. Proxy + auth (OCI mirror with credentials)

Verifies `_proxy_login mi` logs into the mirror registry before image resolution.

```bash
kubectl run mi-test --rm -it --restart=Never \
  --image=rolandhewage/mi-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"mi-test",
        "image":"rolandhewage/mi-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-mi-auth","optional":true}}]
    }
  }'
```

**Expected:** `Logging into proxy mirror: my-mirror.example.com` shown, images resolved to mirror. With a fake mirror, login fails (expected).

### 4a. Maven proxy (fake URL, verify settings.xml is picked up)

Verifies `_setup_maven_proxy mi` generates `settings.xml` with `<mirror>` pointing to proxy URL.

```bash
kubectl run mi-test --rm -it --restart=Never \
  --image=rolandhewage/mi-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"mi-test",
        "image":"rolandhewage/mi-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-mi-maven","optional":true}}]
    }
  }'
```

**Expected:** `_MAVEN_BINDING` shows `--volume /tmp/maven-proxy-binding:/platform/bindings/maven-settings`. With a fake URL, Maven download fails. With a real proxy, build succeeds.

### 4b. Maven proxy with real Nexus

Same as 4a but with a real Nexus Maven proxy URL in the secret.

**Expected:** WSO2 Maven plugins fetched through Nexus Maven proxy, build succeeds.

### 5a. Maven proxy + auth (fake URL, verify settings.xml with credentials)

Verifies `settings.xml` includes `<servers>` section with username/password.

```bash
kubectl run mi-test --rm -it --restart=Never \
  --image=rolandhewage/mi-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"mi-test",
        "image":"rolandhewage/mi-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-mi-maven-auth","optional":true}}]
    }
  }'
```

**Expected:** `settings.xml` has `<servers>` block. With a fake URL, DNS fails (expected).

### 5b. Maven proxy + auth — real Nexus

Same as 5a but with a real Nexus Maven proxy URL and credentials in the secret.

**Expected:** Maven dependencies fetched through authenticated Nexus Maven proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-mi test-proxy-config-mi-mirror test-proxy-config-mi-auth test-proxy-config-mi-maven test-proxy-config-mi-maven-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-maven-url
# e.g., https://abc123.ngrok-free.app/repository/maven-proxy/
```

### Nexus setup for Maven proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **maven2 (proxy)**
2. **Name:** `maven-proxy`, **Remote storage:** `https://repo1.maven.org/maven2/`
3. Repository URL: `http://localhost:8081/repository/maven-proxy/`

### Obtaining credentials for Maven proxy

Use normal Nexus user credentials (username/password).

| K8s Secret key | Value |
|---|---|
| `pkg-maven-url` | Nexus Maven proxy repo URL (e.g. `http://localhost:8081/repository/maven-proxy/`) |
| `pkg-maven-username` | Nexus username (e.g. `admin`) |
| `pkg-maven-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD generates a `settings.xml` with `<mirror>` + `<servers>` and mounts it as a Paketo buildpack binding at `/platform/bindings/maven-settings`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| Lifecycle image configured | After `pack config lifecycle-image` — shows resolved lifecycle image |
| `settings.xml` generated | After `Maven proxy setup` — shows mirror URL |
| `<servers>` present (auth) | `settings.xml` includes `<server>` block with username |
| `_MAVEN_BINDING` set | Shows `--volume /tmp/maven-proxy-binding:/platform/bindings/maven-settings` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Maven uses proxy | NOT WORKING — buildpack ignores CNB binding, Maven goes direct to maven.wso2.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from other tests

| Aspect | Java Maven (buildpack) | MI |
|---|---|---|
| Strategy | `buildpack` | `mi` |
| Builder | Google builder (public, mirrored on ACR) | Choreo custom builder (private ACR only) |
| Lifecycle | Builder default (implicit) | Explicit via `pack config lifecycle-image` |
| Maven binding | Google `GOOGLE_BUILD_ARGS` only (no CNB binding) | Paketo-style CNB binding at `/platform/bindings/maven-settings` |
| Maven settings dir | `/tmp/maven-settings` | `/tmp/maven-proxy-binding` |
| `type` file | No | Yes (`maven`) |
| Package proxy | Maven only | Maven only |
| Secret keys | `oci-buildpacks-*` + `pkg-maven-*` | `oci-buildpacks-*` + `pkg-maven-*` |
| Skipped (E2E) | — | Azure SAS token, `mi_buildpack_subnet` network |

### Key finding: Maven mirroring not consumed by MI buildpack

`choreo/micro-integrator` does NOT read the Paketo-style CNB binding `settings.xml`.
Builds succeed even with a fake Maven proxy URL (scenarios 4a, 5a), proving the mirror
is ignored. The buildpack runs Maven internally without `--settings`.

Two issues: (1) `mi-build-preparation.ts` doesn't pass `$_LANG_ENV` to `pack build`
(only `$_MAVEN_BINDING`), and (2) even if it did, the custom buildpack doesn't read
`GOOGLE_BUILD_ARGS` or CNB bindings.

For restricted clusters, whitelist: `*.blob.core.windows.net`, `maven.wso2.org`, `repo1.maven.org`

## Test results

### 0.1.0 (2026-03-13)

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — `_resolve_image` rewrote to `choreocontrolplane.azurecr.io/...`, ACR login succeeded, all 3 modules built, image built successfully |
| 2 | Proxy (OCI mirror) | PASSED — `_resolve_image` rewrote to `my-mirror.example.com/...`, DNS failed as expected with fake URL |
| 3 | Proxy + auth | PASSED — `_proxy_login mi` attempted login to `my-mirror.example.com`, `_resolve_image` rewrote to mirror, DNS failed as expected |
| 4a | Maven proxy (fake URL) | PASSED — `settings.xml` generated with `<mirror>`, but build succeeded despite fake URL (see key finding above) |
| 4b | Maven proxy (real Nexus) | PASSED — real ngrok Nexus URL in `settings.xml`, build succeeded, same CNB binding observation |
| 5a | Maven proxy + auth (fake URL) | PASSED — `settings.xml` with `<mirror>` + `<servers>`, build succeeded despite fake URL |
| 5b | Maven proxy + auth (real Nexus) | PASSED — real ngrok Nexus URL + auth in `settings.xml`, build succeeded |

E2E image: `rolandhewage/mi-proxy-e2e:0.1.0`
