# Buildpack Java/Gradle — Mirror Registry Test Steps

**What's proxied:**
- `pkg-gradle-url` → generates `init.gradle` with `allprojects { repositories { maven { url } } }`
- Auth: `pkg-gradle-username/password` → `credentials` block in `init.gradle`
- Passed to Gradle via `GRADLE_OPTS=-I /tmp/gradle-proxy-binding/init.gradle`

**Namespace:** `dp-builds-<orgUuid>`

---

## Test 1: No proxy (no secret)

### Setup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```

### Trigger
Trigger a Java/Gradle buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

### Expected
- Build succeeds
- Gradle fetches from default repos
- No init script

---

## Test 2: With Gradle proxy

### Setup
```bash
kubectl create secret generic choreo-build-registry-proxy -n "$NS" \
  --from-literal=pkg-gradle-url="${NGROK_HTTP}/repository/maven-proxy/" \
  --from-literal=pkg-gradle-username="${NEXUS_USER}" \
  --from-literal=pkg-gradle-password="${NEXUS_PASS}"
```

### Trigger
Trigger a Java/Gradle buildpack build from Choreo Console.

### Check logs
```bash
kubectl get pods -n "$NS"
kubectl logs <pod-name> -n "$NS" --all-containers -f --max-log-requests=8
```

Also check ngrok logs at `http://127.0.0.1:4040`.

### Expected
- `--init-script=/tmp/gradle-proxy-binding/init.gradle` in Gradle command
- Dependencies through proxy (check ngrok)
- Build succeeds

### Cleanup
```bash
kubectl delete secret choreo-build-registry-proxy -n "$NS" --ignore-not-found
```
