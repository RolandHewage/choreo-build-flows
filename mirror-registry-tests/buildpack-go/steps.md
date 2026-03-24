# Buildpack Go — Mirror Registry Test Steps

**What's proxied:**
- `pkg-go-url` → `GOPROXY` env var via `pack build --env`
- Auth: `pkg-go-username/password` → `.netrc` file mounted at `/home/cnb/.netrc`
- Also sets `GONOSUMDB=*` when auth is configured

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Go buildpack build.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds, `go mod download` from default `proxy.golang.org`

---

## Test 2: With Go proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-go-url="${NGROK_HTTP}/repository/go-proxy/" \
  --from-literal=pkg-go-username="${NEXUS_USER}" \
  --from-literal=pkg-go-password="${NEXUS_PASS}"
```

### Trigger
Trigger a Go buildpack build with a project that has external deps.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `GOPROXY` set to proxy URL
- `.netrc` mounted with credentials
- `go mod download` fetches through proxy (check ngrok)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Note
Choreo-samples Go projects have no external deps. To fully test, use a project with deps like gin or echo.
