# Buildpack Python — Mirror Registry Test Steps

**What's proxied:**
- `pkg-python-url` → `PIP_INDEX_URL` env var via `pack build --env`
- Auth: `pkg-python-username/password` → embedded in URL as `https://user:pass@host/path`

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Python buildpack build.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds, pip fetches from default `pypi.org`

---

## Test 2: With PyPI proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-python-url="${NGROK_HTTP}/repository/pypi-proxy/simple" \
  --from-literal=pkg-python-username="${NEXUS_USER}" \
  --from-literal=pkg-python-password="${NEXUS_PASS}"
```

### Trigger
Trigger a Python buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `Looking in indexes: https://user:****@ngrok.../repository/pypi-proxy/simple`
- All packages through proxy (ngrok 200 OK)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
