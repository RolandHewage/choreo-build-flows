# Buildpack Ruby — Mirror Registry Test Steps

**What's proxied:** `pkg-rubygems-url` → `Gemfile` source URL modification via `sed`. Auth via `BUNDLE_<HOST>` env var (dots replaced with `__`, dashes with `___`, uppercased).

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Ruby buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Bundler fetches from default `rubygems.org`
- No proxy output

---

## Test 2: With RubyGems proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-rubygems-url="${NGROK_HTTP}/repository/rubygems-proxy/" \
  --from-literal=pkg-rubygems-username="${NEXUS_USER}" \
  --from-literal=pkg-rubygems-password="${NEXUS_PASS}"
```

### Trigger
Trigger a Ruby buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `Gemfile` source URL replaced with proxy URL via `sed`
- `BUNDLE_<HOST>` env var set with credentials (e.g., `BUNDLE_XXXX__NGROK__DEV` for ngrok host)
- Gems fetched through Nexus proxy (ngrok shows 200 OK)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
