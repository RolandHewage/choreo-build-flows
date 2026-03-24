# Buildpack .NET — Mirror Registry Test Steps

**What's proxied:** `pkg-nuget-url` → `NuGet.Config` volume mount at `/home/cnb/.nuget/NuGet/NuGet.Config` (user-level). Auth via `packageSourceCredentials` with `ClearTextPassword`.

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a .NET buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- NuGet restores from default `api.nuget.org`
- No proxy output

---

## Test 2: With NuGet proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-nuget-url="${NGROK_HTTP}/repository/nuget-proxy/index.json" \
  --from-literal=pkg-nuget-username="${NEXUS_USER}" \
  --from-literal=pkg-nuget-password="${NEXUS_PASS}"
```

### Trigger
Trigger a .NET buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `NuGet.Config` mounted at `/home/cnb/.nuget/NuGet/NuGet.Config`
- NuGet packages fetched through Nexus proxy (ngrok shows 200 OK for .nupkg requests)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
