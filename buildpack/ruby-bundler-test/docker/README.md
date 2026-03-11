# Ruby Bundler Proxy E2E Test — Buildpack Flow

E2E test image that runs a real `pack build` for a Ruby app, validating the
Bundler proxy approach for the custom registry proxy CICD pipeline.

## What it tests

The Bundler proxy flow:
- Gemfile `source` URL replaced from `https://rubygems.org` to the proxy URL via `sed`
- Auth via `BUNDLE_<HOST>` env var passed through `pack build --env`
- OCI image resolution via `_resolve_image` (ACR mirror rewrite)
- Registry login via `_proxy_login`

**Why not `.bundle/config` mirror?** Google Cloud Buildpacks Ruby builder explicitly
deletes `.bundle/` before running `bundle install` (confirmed in source:
`cmd/ruby/bundle/lib/lib.go` — `ctx.RemoveAll(".bundle")` called twice).

## Build & push

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/bundler-proxy-e2e:0.1.0 .
docker push rolandhewage/bundler-proxy-e2e:0.1.0
```

> **Note:** Must build as `linux/amd64` — the Google buildpack Ruby runtime is amd64-only.

## K8s Secret keys

| Key | Purpose | Required |
|---|---|---|
| `oci-buildpacks-url` | ACR registry host | Yes |
| `oci-buildpacks-username` | ACR username | Yes |
| `oci-buildpacks-password` | ACR password | Yes |
| `pkg-rubygems-url` | RubyGems proxy URL (e.g. `https://nexus/repository/rubygems-proxy/`) | Scenarios 2 & 3 |
| `pkg-rubygems-username` | RubyGems proxy username | Scenario 3 |
| `pkg-rubygems-password` | RubyGems proxy password | Scenario 3 |

---

## Test scenarios — 0.1.0 (ACR builder, K8s Secret mount)

> All config via K8s Secret volume mount. No env vars needed.

### Prerequisite — create secrets

```bash
# ACR-only (scenario 1)
kubectl create secret generic test-proxy-config-bundler \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>'

# ACR + RubyGems proxy, no auth (scenario 2)
kubectl create secret generic test-proxy-config-bundler-proxy \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-rubygems-url=https://your-proxy/repository/rubygems-proxy/

# ACR + RubyGems proxy + auth (scenario 3)
kubectl create secret generic test-proxy-config-bundler-auth \
  --from-literal=oci-buildpacks-url=choreoprivateacr.azurecr.io \
  --from-literal=oci-buildpacks-username=<acr-username> \
  --from-literal=oci-buildpacks-password='<acr-password>' \
  --from-literal=pkg-rubygems-url=https://your-proxy/repository/rubygems-proxy/ \
  --from-literal=pkg-rubygems-username=<nexus-username> \
  --from-literal=pkg-rubygems-password='<nexus-password>'
```

### 1. No-proxy (ACR only, default flow baseline)

Verifies builds work when only ACR credentials are mounted (no Bundler proxy config).

```bash
kubectl run bundler-test --rm -it --restart=Never \
  --image=rolandhewage/bundler-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"bundler-test",
        "image":"rolandhewage/bundler-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-bundler","optional":true}}]
    }
  }'
```

**Expected:** `bundle install` fetches from `rubygems.org`, build succeeds, prints `E2E TEST PASSED (no-proxy mode)`.

### 2a. Proxy with fake URL (verify Gemfile source replacement)

Verifies Gemfile `source` URL is replaced from `rubygems.org` to proxy URL via `sed`.

```bash
kubectl run bundler-test --rm -it --restart=Never \
  --image=rolandhewage/bundler-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"bundler-test",
        "image":"rolandhewage/bundler-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-bundler-proxy","optional":true}}]
    }
  }'
```

**Expected:** Gemfile source replaced from `rubygems.org` to fake proxy URL. With a fake URL, Bundler fails (DNS or connection error — expected). Prints `E2E TEST PASSED (proxy mode)`.

### 2b. Proxy with real Nexus

Same as 2a but with a real Nexus RubyGems proxy URL in the secret.

**Expected:** Ruby gems (`rack`) fetched through Nexus RubyGems proxy.

### 3a. Proxy with auth — fake URL (verify credential env var)

Verifies `BUNDLE_<HOST>` env var is set with credentials for authenticated proxy.

```bash
kubectl run bundler-test --rm -it --restart=Never \
  --image=rolandhewage/bundler-proxy-e2e:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"bundler-test",
        "image":"rolandhewage/bundler-proxy-e2e:0.1.0",
        "imagePullPolicy":"Always",
        "securityContext":{"privileged":true},
        "volumeMounts":[{"name":"proxy-config","mountPath":"/mnt/proxy-config","readOnly":true}]
      }],
      "volumes":[{"name":"proxy-config","secret":{"secretName":"test-proxy-config-bundler-auth","optional":true}}]
    }
  }'
```

**Expected:** Gemfile source replaced + `BUNDLE_<HOST>` env var added to pack build command. With a fake URL, DNS fails (expected).

### 3b. Proxy with auth — real Nexus

Same as 3a but with a real Nexus RubyGems proxy URL and credentials in the secret.

**Expected:** Ruby gems fetched through authenticated Nexus RubyGems proxy.

### Cleanup secrets

```bash
kubectl delete secret test-proxy-config-bundler test-proxy-config-bundler-proxy test-proxy-config-bundler-auth
```

---

## Testing with local Nexus via ngrok

```bash
# Start ngrok tunnel to local Nexus
ngrok http 8081

# Use the ngrok URL in the K8s Secret as pkg-rubygems-url
# e.g., https://abc123.ngrok-free.app/repository/rubygems-proxy/
```

### Nexus setup for RubyGems proxy

1. Nexus UI -> **Settings** -> **Repositories** -> **Create repository** -> **rubygems (proxy)**
2. **Name:** `rubygems-proxy`, **Remote storage:** `https://rubygems.org`
3. Repository URL: `http://localhost:8081/repository/rubygems-proxy/`

### Obtaining credentials for RubyGems proxy

Use normal Nexus user credentials (username/password).

| K8s Secret key | Value |
|---|---|
| `pkg-rubygems-url` | Nexus RubyGems proxy repo URL (e.g. `http://localhost:8081/repository/rubygems-proxy/`) |
| `pkg-rubygems-username` | Nexus username (e.g. `admin`) |
| `pkg-rubygems-password` | Nexus password |

To require authentication: Nexus UI -> **Settings** -> **Security** -> **Anonymous** -> disable **Allow anonymous access**.

The CICD uses `sed` to replace the `https://rubygems.org` source URL in the Gemfile with the proxy URL. For authenticated proxies, a `BUNDLE_<HOST>` env var is passed via `pack build --env` (Bundler reads `BUNDLE_` prefixed env vars automatically for host credentials).

## What to check in logs

| Check | Where in output |
|---|---|
| Proxy config files listed | After `Proxy config (/mnt/proxy-config/)` |
| Images resolved correctly | After `Resolve images via _resolve_image` — original `choreoprivateacr.azurecr.io/...` -> resolved to mirror |
| Gemfile source replaced | After `Replacing rubygems.org source in Gemfile` — shows before/after |
| Credentials env var added | `Added credentials for <host> via BUNDLE_<HOST>` |
| ACR login succeeded | After `Logging into proxy mirror:` |
| Bundler uses proxy | During BUILDING phase — should fetch from proxy URL, NOT rubygems.org |
| Build completes | `E2E TEST PASSED` at the end |

## Key finding: `.bundle/config` mirror doesn't work

Google Cloud Buildpacks Ruby builder (`google.ruby.bundle`) explicitly deletes `.bundle/`
before running `bundle install`. This was confirmed by reading the buildpack source code
(`cmd/ruby/bundle/lib/lib.go` — `ctx.RemoveAll(".bundle")` called twice).

This means any `.bundle/config` with mirror settings placed in the project directory
is deleted before Bundler runs, making it ineffective. The Gemfile source modification
approach works because `sed` changes the actual Gemfile, which the buildpack reads directly.

## Key difference from other tests

| Aspect | Composer (PHP) | Bundler (Ruby) |
|---|---|---|
| Proxy mechanism | Inject into `composer.json` via `jq` | Replace Gemfile `source` URL via `sed` |
| Auth mechanism | `auth.json` in project root | `BUNDLE_<HOST>` env var via `--env` |
| Modifies source? | Yes (`composer.json`) | Yes (`Gemfile`) |
| Detection file | `composer.json` | `Gemfile` |
| Tool needed | `jq` | `sed` (no extra tools) |
| Why not config file? | N/A | Google buildpack deletes `.bundle/` |
