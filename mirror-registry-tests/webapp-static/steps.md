# Webapp Static Files — Mirror Registry Test Steps

**What's proxied:** Only OCI image for nginx via `oci-choreo-url` or `image-nginx-ref`. No Node, no npm — just static files served by nginx.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a static webapp build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Nginx image pulled from `choreoanonymouspullable.azurecr.io`
- No Node, no npm install

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
Trigger a static webapp build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: fake-mirror.example.com` appears in logs
- `podman login` attempted, fails with DNS error (expected)
- Build fails — correct behavior (bad mirror should fail the build)

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
