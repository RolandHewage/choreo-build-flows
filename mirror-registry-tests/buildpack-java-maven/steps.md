# Buildpack Java/Maven — Mirror Registry Test Steps

**What's proxied:**
- OCI images: builder, lifecycle, run via `_resolve_image buildpack`
- Package proxy: `pkg-maven-url` → Maven `settings.xml` with `<mirror>`, mounted as CNB binding at `/platform/bindings/maven-settings/settings.xml`
- Auth: `pkg-maven-username/password` → `<server>` block in `settings.xml`
- `_proxy_login buildpack` for OCI mirror auth

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Java/Maven buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Maven fetches from default repos (`repo1.maven.org`)
- No proxy output

---

## Test 2: With Maven proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-maven-url="${NGROK_HTTP}/repository/maven-proxy/" \
  --from-literal=pkg-maven-username="${NEXUS_USER}" \
  --from-literal=pkg-maven-password="${NEXUS_PASS}"
```

### Trigger
Trigger a Java/Maven buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- Maven uses `--settings=/platform/bindings/maven-settings/settings.xml`
- Maven artifacts downloaded through Nexus proxy (ngrok shows 200 OK for .jar/.pom requests)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
