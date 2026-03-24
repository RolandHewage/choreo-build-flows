# MI (Micro Integrator) — Mirror Registry Test Steps

**What's proxied:**
- OCI images: builder, lifecycle, run via `_resolve_image mi`
- Maven proxy: `_setup_maven_proxy mi` → `settings.xml` binding mounted at `/platform/bindings/maven-settings/settings.xml`
- `_proxy_login mi` for OCI mirror auth

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger an MI build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Maven fetches from default repos (`repo1.maven.org`)
- OCI images pulled from default registries
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
Trigger an MI build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `settings.xml` binding mounted with mirror config
- Maven artifacts downloaded through Nexus proxy (ngrok shows 200 OK for .jar/.pom requests)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

---

## Test 3: With real OCI buildpacks creds

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-buildpacks-url="<mirror-registry-host>" \
  --from-literal=oci-buildpacks-username="<mirror-registry-username>" \
  --from-literal=oci-buildpacks-password="<mirror-registry-password>"
```

### Trigger
Trigger an MI build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `_proxy_login mi` logs `Logging into proxy mirror: <mirror-registry-host>`
- Builder, lifecycle, and run images resolved via `_resolve_image mi` to mirror registry
- Build succeeds (requires images to actually exist in the mirror)

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
