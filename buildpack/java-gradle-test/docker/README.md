# Java Gradle Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Java Gradle app, validating the
custom registry proxy CICD pipeline for Gradle dependencies.

## What it tests

The Gradle proxy flow from `buildpack-build.ts` + `workflow-resources.ts`:
- `init.gradle` generated with `allprojects { repositories { maven { url "..." } } }`
- Optional `credentials` block with username/password for authenticated proxies
- `init.gradle` volume-mounted into build container via `_LANG_VOLUMES`
- `GOOGLE_BUILD_ARGS=--init-script=/tmp/gradle-proxy-binding/init.gradle` passed via `_LANG_ENV`
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/gradle-proxy-e2e:0.1.0 .
docker push rolandhewage/gradle-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Java runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-gradle-url` | Gradle/Maven proxy URL (e.g. `https://nexus/repository/maven-proxy/`) | Scenarios 2 & 3 |
| `pkg-gradle-username` | Gradle proxy username | Scenario 3 |
| `pkg-gradle-password` | Gradle proxy password | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-gradle \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + Gradle proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-gradle-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-gradle-url=https://your-proxy/repository/maven-proxy/

# ACR + Gradle proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-gradle-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-gradle-url=https://your-proxy/repository/maven-proxy/ \
  --from-literal=pkg-gradle-username=<nexus-username> \
  --from-literal=pkg-gradle-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no Gradle proxy config).

```bash
kubectl run gradle-test --rm -it --restart=Never \
  --image=rolandhewage/gradle-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"gradle-test",
        "image":"rolandhewage/gradle-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-gradle","optional":true}}]
    }
  }'
```

**Expected:** Gradle fetches from Maven Central (default `mavenCentral()` in `build.gradle`), build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify init.gradle is picked up)

Verifies `init.gradle` is generated and `GOOGLE_BUILD_ARGS=--init-script=<path>` is set.

```bash
kubectl run gradle-test --rm -it --restart=Never \
  --image=rolandhewage/gradle-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"gradle-test",
        "image":"rolandhewage/gradle-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-gradle-proxy","optional":true}}]
    }
  }'
```

**Expected:** `_LANG_ENV` shows `--env GOOGLE_BUILD_ARGS=--init-script=/tmp/gradle-proxy-binding/init.gradle`. With a fake URL, Gradle dependency resolution fails. With a real proxy, build succeeds.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus Maven proxy URL in the secret.

**Expected:** Gradle dependencies (`gson`) fetched through Nexus Maven proxy.

### 3a. Proxy with auth — fake URL (verify init.gradle with credentials)

Verifies `init.gradle` includes `credentials` block with username/password.

```bash
kubectl run gradle-test --rm -it --restart=Never \
  --image=rolandhewage/gradle-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"gradle-test",
        "image":"rolandhewage/gradle-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-gradle-auth","optional":true}}]
    }
  }'
```

**Expected:** `init.gradle` has `credentials` block. With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus Maven proxy URL and credentials in the secret.

**Expected:** Gradle dependencies fetched through authenticated Nexus Maven proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-gradle test-proxy-config-gradle-proxy test-proxy-config-gradle-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-gradle-url
# e.g., https://abc123.ngrok-free.app/repository/maven-proxy/
```

### Nexus setup for Maven proxy (used by Gradle)

Gradle uses Maven repositories, so the same Nexus Maven proxy works for both Maven and Gradle.

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **maven2 (proxy)**
2. **Name:** `maven-proxy`, **Remote storage:** `https://repo1.maven.org/maven2/`
3. Repository URL: `http://localhost:8081/repository/maven-proxy/`

### Obtaining credentials for Gradle proxy

Use normal Nexus user credentials (username/password).

| K8s Secret key | Value |
|---|---|
| `pkg-gradle-url` | Nexus Maven proxy repo URL (e.g. `http://localhost:8081/repository/maven-proxy/`) |
| `pkg-gradle-username` | Nexus username (e.g. `admin`) |
| `pkg-gradle-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD generates an `init.gradle` file that overrides all project repositories with the proxy URL. The `init.gradle` is volume-mounted into the build container and passed via `GOOGLE_BUILD_ARGS=--init-script=/tmp/gradle-proxy-binding/init.gradle`.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `init.gradle` generated | After `Generated init.gradle` — shows maven URL |
| `credentials` present (auth) | `init.gradle` includes `credentials { username = "..." }` |
| `GOOGLE_BUILD_ARGS` set | `_LANG_ENV` line shows `--env GOOGLE_BUILD_ARGS=--init-script=/tmp/gradle-proxy-binding/init.gradle` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Gradle uses proxy | During BUILDING phase — should show proxy URL, NOT repo1.maven.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key difference from Maven test

| Aspect | Java (Maven) | Java (Gradle) |
|---|---|---|
| Proxy mechanism | `settings.xml` with `<mirror>` | `init.gradle` with `allprojects { repositories { maven { ... } } }` |
| Auth handling | `<servers>` section in `settings.xml` | `credentials` block in `init.gradle` |
| Mounting method | `_MAVEN_BINDING` (volume mount) + `GOOGLE_BUILD_ARGS=--settings=<path>` | `_LANG_VOLUMES` (volume mount) + `GOOGLE_BUILD_ARGS=--init-script=<path>` |
| Config path | `/platform/bindings/maven-settings/settings.xml` | `/tmp/gradle-proxy-binding/init.gradle` |
| Secret keys | `pkg-maven-*` | `pkg-gradle-*` |
| Detection file | `pom.xml` | `build.gradle` |

## Test results

### 0.1.0

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — JDK v21.0.10 from `dl.google.com`, Gradle v9.4.0 from `services.gradle.org`, `gson:2.10.1` from Maven Central, build succeeded (7.1s) |
| 2a | Proxy (fake URL, no auth) | PASSED — `--init-script=/tmp/gradle-proxy-binding/init.gradle` appended via `GOOGLE_BUILD_ARGS`, Gradle tried `https://your-proxy/repository/maven-proxy/`, DNS failed as expected (`your-proxy: Name or service not known`), `clear()` prevented Maven Central fallback |
| 2b | Proxy (real Nexus, no auth) | PASSED — Gradle deps fetched through ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), `--init-script` via `GOOGLE_BUILD_ARGS`, build succeeded (7.9s) |
| 3a | Proxy + auth (fake URL) | PASSED — `init.gradle` with `credentials` block generated, Gradle tried `https://your-proxy/repository/maven-proxy/`, DNS failed as expected (`your-proxy: Name or service not known`) |
| 3b | Proxy + auth (real Nexus) | PASSED — Gradle deps fetched through authenticated ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), `init.gradle` with `credentials` block, build succeeded (8.9s) |
