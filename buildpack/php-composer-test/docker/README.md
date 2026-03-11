# PHP Composer Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a PHP app, validating the
Composer proxy approach for the custom registry proxy CICD pipeline.

## What it tests

The proposed Composer proxy flow:
- Proxy repository injected directly into project's `composer.json` (with `packagist.org: false`)
- No `--volume` mount needed for Composer config (avoids `pack build` read-only volume issue)
- Optional `auth.json` written next to `composer.json` with `http-basic` credentials for authenticated proxies
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/composer-proxy-e2e:0.1.0 .
docker push rolandhewage/composer-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack PHP runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-composer-url` | Composer proxy URL (e.g. `https://nexus/repository/composer-proxy/`) | Scenarios 2 & 3 |
| `pkg-composer-username` | Composer proxy username | Scenario 3 |
| `pkg-composer-password` | Composer proxy password | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-composer \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + Composer proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-composer-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-composer-url=https://your-proxy/repository/composer-proxy/

# ACR + Composer proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-composer-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-composer-url=https://your-proxy/repository/composer-proxy/ \
  --from-literal=pkg-composer-username=<nexus-username> \
  --from-literal=pkg-composer-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no Composer proxy config).

```bash
kubectl run composer-test --rm -it --restart=Never \
  --image=rolandhewage/composer-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"composer-test",
        "image":"rolandhewage/composer-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-composer","optional":true}}]
    }
  }'
```

**Expected:** `composer install` fetches from `packagist.org`, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify config.json is picked up)

Verifies proxy repository is injected into `composer.json` and `packagist.org` is disabled.

```bash
kubectl run composer-test --rm -it --restart=Never \
  --image=rolandhewage/composer-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"composer-test",
        "image":"rolandhewage/composer-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-composer-proxy","optional":true}}]
    }
  }'
```

**Expected:** `composer.json` updated with proxy repository and `packagist.org: false`. With a fake URL, Composer fails (DNS or connection error — expected). With a real proxy, build succeeds.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus Composer proxy URL in the secret.

**Expected:** Composer packages (`monolog`) fetched through Nexus Composer proxy.

### 3a. Proxy with auth — fake URL (verify auth.json generation)

Verifies `auth.json` is generated with `http-basic` credentials next to `composer.json`.

```bash
kubectl run composer-test --rm -it --restart=Never \
  --image=rolandhewage/composer-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"composer-test",
        "image":"rolandhewage/composer-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-composer-auth","optional":true}}]
    }
  }'
```

**Expected:** `COMPOSER_AUTH` shows `http-basic` JSON (password masked). With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus Composer proxy URL and credentials in the secret.

**Expected:** Composer packages fetched through authenticated Nexus Composer proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-composer test-proxy-config-composer-proxy test-proxy-config-composer-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-composer-url
# e.g., https://abc123.ngrok-free.app/repository/composer-proxy/
```

### Nexus setup for Composer proxy

1. Nexus UI → **Settings** → **Repositories** → **Create repository** → **composer (proxy)**
2. **Name:** `composer-proxy`, **Remote storage:** `https://packagist.org`
3. Repository URL: `http://localhost:8081/repository/composer-proxy/`

> **Note:** Nexus requires the `nexus-repository-composer` plugin for Composer proxy support.

### Obtaining credentials for Composer proxy

Use normal Nexus user credentials (username/password).

| K8s Secret key | Value |
|---|---|
| `pkg-composer-url` | Nexus Composer proxy repo URL (e.g. `http://localhost:8081/repository/composer-proxy/`) |
| `pkg-composer-username` | Nexus username (e.g. `admin`) |
| `pkg-composer-password` | Nexus password |

To require authentication: Nexus UI → **Settings** → **Security** → **Anonymous** → disable **Allow anonymous access**.

The CICD injects the proxy repository directly into the project's `composer.json` (disabling packagist.org), redirecting all Composer downloads through the proxy. For authenticated proxies, `COMPOSER_AUTH` env var provides `http-basic` credentials.

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` → resolved to mirror |
| `composer.json` updated | After `Injecting proxy repository into composer.json` — shows proxy URL and `packagist.org: false` |
| `COMPOSER_AUTH` set (auth) | `COMPOSER_AUTH set (password masked)` — shows `http-basic` JSON |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Composer uses proxy | During BUILDING phase — should fetch from proxy, NOT packagist.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key validation point

This E2E test validates that the Google Cloud Buildpacks PHP builder respects proxy repository config injected into `composer.json`. The `COMPOSER_HOME` volume mount approach does NOT work — `pack build` volume mounts are read-only for the CNB user, and the Composer installer needs to write key files (`keys.dev.pub`) there.

## Key difference from other tests

| Aspect | Go | npm (buildpack) | Composer (PHP) |
|---|---|---|---|
| Proxy mechanism | `GOPROXY` env var | `NPM_CONFIG_REGISTRY` env var | Inject into `composer.json` |
| Auth handling | `.netrc` mounted at `/home/cnb/.netrc` | `.npmrc` mounted at `/home/cnb/.npmrc` | `COMPOSER_AUTH` env var (JSON) |
| Disable default registry | N/A (GOPROXY replaces) | N/A (env var overrides) | `"packagist.org": false` in `config.json` |
| Variable accumulated | `_LANG_ENV` + `_LANG_VOLUMES` | `_LANG_ENV` + `_LANG_VOLUMES` | `_LANG_ENV` + `_LANG_VOLUMES` |
| Secret keys | `pkg-go-*` | `pkg-npm-url`, `pkg-npm-token` | `pkg-composer-*` |
| Detection file | `go.mod` | `package.json` | `composer.json` |

## Test results

### 0.1.0

| # | Scenario | Result |
|---|---|---|
| 1 | No-proxy (ACR only) | PASSED — PHP 8.4.18 from `dl.google.com`, Composer v2.2.24 from `getcomposer.org`, `monolog/monolog:3.10.0` + `psr/log:3.0.2` from packagist.org, build succeeded (3.1s) |
| 2a | Proxy (fake URL, no auth) | PASSED — `COMPOSER_MIRROR_PATH_REPOS=1` + `COMPOSER_HOME=/tmp/composer-proxy-auth` set, `auth.json` with bearer token generated and volume-mounted, Composer tried `https://your-proxy/repository/composer-proxy/packages.json`, `Could not resolve host: your-proxy` as expected, default Packagist bypassed |
| 2b | Proxy (real Nexus, no auth) | PASSED — Composer packages fetched through ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), `monolog/monolog:3.10.0` + `psr/log:3.0.2` from proxy, build succeeded (4.7s) |
| 3a | Proxy + auth (fake URL) | PASSED — `auth.json` with `http-basic` credentials generated in project directory (no COMPOSER_AUTH env var issues), proxy repository injected into `composer.json` with `packagist.org: false`, Composer tried `https://your-proxy/repository/composer-proxy/packages.json`, `Could not resolve host: your-proxy` as expected |
| 3b | Proxy + auth (real Nexus) | PASSED — `auth.json` with `http-basic` credentials generated in project directory, Composer packages fetched through authenticated ngrok → local Nexus proxy (`fafe-203-94-95-14.ngrok-free.app`), `monolog/monolog:3.10.0` + `psr/log:3.0.2` from proxy, build succeeded (2.4s) |
