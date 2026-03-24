# Buildpack PHP — Mirror Registry Test Steps

**What's proxied:** `pkg-composer-url` → modifies `composer.json` via `jq` to add proxy repository. Auth via `auth.json` with `http-basic` credentials.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a PHP buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Composer fetches from default `packagist.org`
- No proxy output

---

## Test 2: With Composer proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-composer-url="${NGROK_HTTP}/repository/composer-proxy/" \
  --from-literal=pkg-composer-username="${NEXUS_USER}" \
  --from-literal=pkg-composer-password="${NEXUS_PASS}"
```

### Trigger
Trigger a PHP buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `composer.json` modified to include proxy repository via `jq`
- `auth.json` created with `http-basic` credentials for the proxy host
- Composer packages fetched through Nexus proxy (ngrok shows 200 OK)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
