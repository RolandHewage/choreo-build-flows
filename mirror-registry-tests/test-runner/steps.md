# Test Runner — Mirror Registry Test Steps

**What's proxied:**
- OCI Node image via `_resolve_image test-runner`
- npm proxy via `--build-arg NPM_REGISTRY` + `.npmrc` secret mount (same pattern as webapp)
- `_proxy_login test-runner` for OCI mirror auth

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a test-runner build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- npm fetches from default `registry.npmjs.org`
- Node image pulled from default `docker.io`
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
Trigger a test-runner build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `--build-arg NPM_REGISTRY=<ngrok URL>` passed to build
- `.npmrc` secret mount with `_authToken` for proxy auth
- npm packages fetched through Nexus proxy (ngrok shows 200 OK)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
