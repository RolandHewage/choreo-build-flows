# BYOC — Mirror Registry Test Steps

**What's proxied:** `_proxy_login byoc` → `podman login` to configured OCI mirrors. No image rewriting or package proxy — customer manages deps in their own Dockerfile.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a BYOC build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- No proxy-related output in logs
- `FROM` images pulled from public registries directly
- `Login Succeeded!` only for ACR

---

## Test 2: With proxy (fake mirror — verifies proxy login runs)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-dockerhub-url="fake-mirror.example.com" \
  --from-literal=oci-dockerhub-username="testuser" \
  --from-literal=oci-dockerhub-password="testpass"
```

### Trigger
Trigger a BYOC build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: fake-mirror.example.com` appears in logs
- `podman login` attempted, fails with DNS error (expected for fake URL)
- Build fails with exit code 125 due to `set -e` — **correct behavior**
- Bad credentials/unreachable mirror should fail the build (customer must fix their config)

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
