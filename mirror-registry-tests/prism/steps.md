# Prism Mock — Mirror Registry Test Steps

**What's proxied:**
- OCI images: Prism image via `oci-choreo-url` or `image-prism-ref`, Golang image via `image-golang-ref`
- Package proxy: npm via `_setup_npm_proxy prism` (for `prism-docker-resource-generator` script)
- `_proxy_login prism` for OCI mirror auth

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Prism mock build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Prism image from `choreocontrolplane.azurecr.io/stoplight/prism:5`
- Golang image from `choreocontrolplane.azurecr.io/golang:1.22.4-alpine`
- `npm install` runs (2 packages for prism-docker-resource-generator)
- No proxy output in logs

---

## Test 2: With proxy (fake OCI mirror)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-choreo-url="fake-mirror.example.com" \
  --from-literal=oci-choreo-username="testuser" \
  --from-literal=oci-choreo-password="testpass"
```

### Trigger
Trigger a Prism mock build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: fake-mirror.example.com` in logs
- Build fails — correct behavior (fake mirror unreachable)

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

---

## Test 3: With npm proxy (optional — tests npm proxy for prism)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-npm-url="${NGROK_HTTP}/repository/npm-proxy/" \
  --from-literal=pkg-npm-token="$(echo -n '${NEXUS_USER}:${NEXUS_PASS}' | base64)"
```

### Trigger
Trigger a Prism mock build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `npm install` fetches through Nexus proxy
- ngrok logs show requests

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
