# Webapp Vue — Mirror Registry Test Steps

**What's proxied:** Same as React — `pkg-npm-url` → `--build-arg NPM_REGISTRY` + `.npmrc` secret mount. Node image via `oci-dockerhub-url`, Nginx image via `oci-choreo-url`.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Vue webapp build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- `missing "NPM_REGISTRY" build argument` warning (expected)
- `npm install` fetches from default registry
- `vue-cli-service build` succeeds

---

## Test 2: With npm proxy

### Setup
Same secret as React/Angular test:
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-npm-url="${NGROK_HTTP}/repository/npm-proxy/" \
  --from-literal=pkg-npm-token="$(echo -n '${NEXUS_USER}:${NEXUS_PASS}' | base64)"
```

### Trigger
Trigger a Vue webapp build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `npm install` fetches packages through Nexus proxy
- ngrok shows 200 OK for package requests
- `vue-cli-service build` succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
