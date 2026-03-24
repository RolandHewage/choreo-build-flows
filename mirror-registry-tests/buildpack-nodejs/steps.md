# Buildpack Node.js — Mirror Registry Test Steps

**What's proxied:** `pkg-npm-url` → `NPM_CONFIG_REGISTRY` env var via `pack build --env`. Auth via `pkg-npm-token` → `.npmrc` mounted at `/home/cnb/.npmrc` with `_authToken`.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Node.js buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- npm fetches from default `registry.npmjs.org`
- No proxy output

---

## Test 2: With npm proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-npm-url="${NGROK_HTTP}/repository/npm-proxy/" \
  --from-literal=pkg-npm-token="$(echo -n '${NEXUS_USER}:${NEXUS_PASS}' | base64)"
```

### Trigger
Trigger a Node.js buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `NPM_CONFIG_REGISTRY` set to ngrok proxy URL
- `.npmrc` mounted at `/home/cnb/.npmrc` with `_authToken`
- npm packages fetched through Nexus proxy (ngrok shows 200 OK)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
