# Ballerina — Mirror Registry Test Steps

**What's proxied:**
- OCI images: lifecycle via `_resolve_image ballerina image-buildpacks-lifecycle-ref oci-buildpacks-url`, builder via `_resolve_image ballerina image-buildpacks-builder-ref oci-buildpacks-url`
- `_proxy_login ballerina` for OCI mirror auth
- No package proxy — Ballerina Central (`dev-central.ballerina.io`) is not proxied

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Ballerina build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Uses Choreo buildpack `choreoipaas/choreo-buildpacks/builder:0.2.107`
- Ballerina deps from `dev-central.ballerina.io`
- No proxy output

---

## Test 2: With proxy — `oci-choreo-url` (fake mirror)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-choreo-url="fake-mirror.example.com" \
  --from-literal=oci-choreo-username="testuser" \
  --from-literal=oci-choreo-password="testpass"
```

### Trigger
Trigger a Ballerina build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: fake-mirror.example.com` in logs
- Build fails — correct behavior

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

---

## Test 3: With proxy — `oci-buildpacks-url` (fake mirror)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-buildpacks-url="fake-mirror.example.com" \
  --from-literal=oci-buildpacks-username="testuser" \
  --from-literal=oci-buildpacks-password="testpass"
```

### Trigger
Trigger a Ballerina build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: fake-mirror.example.com` in logs
- Build fails — correct behavior

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

---

## Test 4: With proxy — `oci-buildpacks-url` (real ACR credentials)

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=oci-buildpacks-url="<mirror-registry-host>" \
  --from-literal=oci-buildpacks-username="<mirror-registry-username>" \
  --from-literal=oci-buildpacks-password="<mirror-registry-password>"
```

### Trigger
Trigger a Ballerina build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- `Logging into proxy mirror: <mirror-registry-host>` → `Login Succeeded!`
- All images pulled successfully: lifecycle, builder, run
- Full Ballerina build completed
- Image exported and pushed to ACR

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
