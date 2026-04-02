# Java Maven Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Java Maven app, validating the
custom registry proxy CICD pipeline for Maven dependencies.

## What it tests

The Maven proxy flow from `buildpack-build.ts` + `workflow-resources.ts`:
- `settings.xml` generated with `<mirror>` redirecting `*` to proxy URL
- Optional `<servers>` section with username/password for authenticated proxies
- `settings.xml` mounted as buildpack service binding at `/platform/bindings/maven-settings` via `_MAVEN_BINDING`
- `type` file written with value `maven` (required by buildpack binding spec)
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

## Image versions

| Version | Entrypoint | Notes |
|---|---|---|
| `0.1.0` | `entrypoint-0.1.0.sh` | K8s Secret mount, Maven binding at `/maven-settings/settings.xml` |
| `0.2.0` | `entrypoint.sh` | Added `GOOGLE_RUNTIME_IMAGE_REGION=us`. Fixed Maven binding to `/platform/bindings/maven-settings` with `type` file (matching production). |

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/maven-proxy-e2e:0.2.0 .
docker push rolandhewage/maven-proxy-e2e:0.2.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Java runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-maven-url` | Maven proxy URL (e.g. `https://nexus/repository/maven-proxy/`) | Scenarios 2 & 3 |
| `pkg-maven-username` | Maven proxy username | Scenario 3 |
| `pkg-maven-password` | Maven proxy password | Scenario 3 |

---

## Test scenarios — 0.2.0 (ACR builder, K8s Secret mount, GOOGLE_RUNTIME_IMAGE_REGION=us)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-maven \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + Maven proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-maven-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-maven-url=https://your-proxy/repository/maven-proxy/

# ACR + Maven proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-maven-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-maven-url=https://your-proxy/repository/maven-proxy/ \
  --from-literal=pkg-maven-username=<nexus-username> \
  --from-literal=pkg-maven-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no Maven proxy config).

```bash
kubectl run maven-test --rm -it --restart=Never \
  --image=rolandhewage/maven-proxy-e2e:0.2.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"maven-test",
        "image":"rolandhewage/maven-proxy-e2e:0.2.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-maven","optional":true}}]
    }
  }'
```

**Expected:** Maven fetches from Maven Central, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify settings.xml is picked up)

Verifies `settings.xml` is generated with `<mirror>` pointing to proxy URL.

```bash
kubectl run maven-test --rm -it --restart=Never \
  --image=rolandhewage/maven-proxy-e2e:0.2.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"maven-test",
        "image":"rolandhewage/maven-proxy-e2e:0.2.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-maven-proxy","optional":true}}]
    }
  }'
```

**Expected:** `_MAVEN_BINDING` shows `--volume /tmp/maven-proxy-binding:/platform/bindings/maven-settings`. With a fake URL, Maven download fails. With a real proxy, build succeeds.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus Maven proxy URL in the secret.

**Expected:** Maven dependencies (`gson`) fetched through Nexus Maven proxy.

### 3a. Proxy with auth — fake URL (verify settings.xml with credentials)

Verifies `settings.xml` includes `<servers>` section with username/password.

```bash
kubectl run maven-test --rm -it --restart=Never \
  --image=rolandhewage/maven-proxy-e2e:0.2.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"maven-test",
        "image":"rolandhewage/maven-proxy-e2e:0.2.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-maven-auth","optional":true}}]
    }
  }'
```

**Expected:** `settings.xml` has `<servers>` block. With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus Maven proxy URL and credentials in the secret.

**Expected:** Maven dependencies fetched through authenticated Nexus Maven proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-maven test-proxy-config-maven-proxy test-proxy-config-maven-auth
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

The CICD generates a `settings.xml` with `<mirror>` + `<servers>` and mounts it as a buildpack service binding at `/platform/bindings/maven-settings`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `settings.xml` generated | After `Generated settings.xml` — shows mirror URL |
| `<servers>` present (auth) | `settings.xml` includes `<server>` block with username |
| `_MAVEN_BINDING` set | Shows `--volume /tmp/maven-proxy-binding:/platform/bindings/maven-settings` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Maven uses proxy | During BUILDING phase — should show proxy URL, NOT repo1.maven.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from Go test

| Aspect | Go | Java (Maven) |
|---|---|---|
| Proxy mechanism | `GOPROXY` env var | `settings.xml` with `<mirror>` via `GOOGLE_BUILD_ARGS` |
| Auth handling | `.netrc` file mounted at `/home/cnb/.netrc` | `<servers>` section in `settings.xml` |
| Mounting method | `_LANG_VOLUMES` (volume mount) | `_MAVEN_BINDING` (volume mount) + `GOOGLE_BUILD_ARGS=--settings=<path>` |
| Secret keys | `pkg-go-url`, `pkg-go-username`, `pkg-go-password` | `pkg-maven-url`, `pkg-maven-username`, `pkg-maven-password` |
| Detection file | `go.mod` | `pom.xml` |

### Google buildpacks vs Paketo — Maven settings

Google buildpacks (`google.java.maven`) do **NOT** support CNB service bindings.
The `settings.xml` must be passed via `GOOGLE_BUILD_ARGS=--settings=<path>` and
volume-mounted into the build container. The original CICD implementation
(`constructPkgMavenSettings()` in `workflow-resources.ts`) uses the Paketo-style
binding at `/platform/bindings/maven-settings` which is silently ignored by the
Google builder.

## Podman v5 / Harvester compatibility

After the cluster update to Harvester, podman v5 (Alpine 3.21) raises the minimum
Docker-compatible API to **1.44**. The CNB lifecycle image (`buildpacksio/lifecycle:0.20.2`)
uses a Docker client that defaults to API **1.41**, which podman v5 rejects:

```
ERROR: failed to initialize analyzer: getting previous image: inspecting image "...":
  API version 1.41 is not supported by this client: the minimum supported API version is 1.44
```

**Why `export DOCKER_API_VERSION=1.44` alone is not enough:**
- `export` in the shell only affects the `pack` CLI process itself
- `--env DOCKER_API_VERSION=1.44` on `pack build` only reaches build/detect phases
- Neither reaches the **lifecycle containers** (analyze, restore, export phases)

**Fix — one line in the Dockerfile:**

```dockerfile
printf '[containers]\nenv = ["DOCKER_API_VERSION=1.44"]\n' > /etc/containers/containers.conf
```

This tells podman to inject `DOCKER_API_VERSION=1.44` into ALL containers it creates,
including the lifecycle containers that pack spawns internally.

**Production impact:** The production `argo-base-images/buildpack-build/Dockerfile`
uses Alpine 3.21 (podman v5) but does NOT have this `containers.conf` fix.
Production buildpack/MI/Ballerina builds will hit the same error.
The same one-line fix needs to be applied to the production Dockerfile.

---

## Test results

### 0.1.0

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — JDK v21.0.10 from `dl.google.com`, Maven v3.9.11 from `archive.apache.org`, `gson:2.10.1` from Maven Central, build succeeded (15.8s) |
| 2a | Proxy (fake URL, no auth) | PASSED — `--settings=/maven-settings/settings.xml` appended via `GOOGLE_BUILD_ARGS`, Maven tried `proxy-mirror (https://your-proxy/repository/maven-proxy/)`, DNS failed as expected (`your-proxy: Name or service not known`) |
| 2b | Proxy (real Nexus, no auth) | PASSED — Maven deps fetched through ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), build succeeded (1m31s vs 23s no-proxy due to ngrok latency) |
| 3a | Proxy + auth (fake URL) | PASSED — `settings.xml` with `<mirror>` + `<servers>` generated, Maven tried `proxy-mirror (https://your-proxy/repository/maven-proxy/)`, DNS failed as expected |
| 3b | Proxy + auth (real Nexus) | PASSED — Maven deps fetched through authenticated ngrok → local Nexus proxy, `settings.xml` with `<mirror>` + `<servers>`, build succeeded (1m4s) |

### 0.2.0 (2026-04-02)

Added `GOOGLE_RUNTIME_IMAGE_REGION=us` and fixed Maven binding path to `/platform/bindings/maven-settings` with `type` file.

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy | PASSED — JDK v21.0.10 (`canonicaljdk`) from `us-docker.pkg.dev`, Maven v3.9.11 from `archive.apache.org`, deps from Maven Central, build succeeded (6.5s) |
| 2 | Proxy (real Nexus, no auth) | PASSED — JDK v21.0.10 (`canonicaljdk`) from `us-docker.pkg.dev`, Maven v3.9.11 from `archive.apache.org`, deps through ngrok Nexus proxy (2m21s), `--settings=/platform/bindings/maven-settings/settings.xml` confirmed |
| 3 | Proxy + auth (real Nexus) | PASSED — JDK v21.0.10 (`canonicaljdk`) from `us-docker.pkg.dev`, Maven v3.9.11 from `archive.apache.org`, deps through ngrok Nexus proxy, `--settings=/platform/bindings/maven-settings/settings.xml` confirmed |
