# Webapp React — Mirror Registry Test Steps

**What's proxied:** `pkg-npm-url` → `--build-arg NPM_REGISTRY` + `.npmrc` secret mount with `_authToken`. Node image via `oci-dockerhub-url`, Nginx image via `oci-choreo-url`.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a React webapp build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- `missing "NPM_REGISTRY" build argument` warning (expected — ARG declared but no --build-arg passed)
- `npm install` fetches from default `registry.npmjs.org`
- Node image from `docker.io`, nginx from `choreoanonymouspullable.azurecr.io`

---

## Test 2: With npm proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-npm-url="${NGROK_HTTP}/repository/npm-proxy/" \
  --from-literal=pkg-npm-token="$(echo -n '${NEXUS_USER}:${NEXUS_PASS}' | base64)"
```

### Trigger
Trigger a React webapp build from Choreo Console.

### Check logs
```bash
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `--build-arg NPM_REGISTRY=<ngrok URL>` in logs (no "missing" warning)
- `npm install` fetches packages through Nexus proxy
- ngrok shows 200 OK for package requests
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
