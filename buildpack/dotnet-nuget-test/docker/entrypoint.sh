#!/bin/sh
set -e

# =============================================================================
# E2E test of buildpack NuGet proxy flow with actual pack build.
# Uses Google buildpacks builder (gcr.io/buildpacks/builder:google-22)
# matching the actual Choreo dotnet build flow.
#
# Two runtime modes (auto-detected):
#   LOCAL   — Docker socket mounted at /var/run/docker.sock
#   CLUSTER — podman running in privileged pod
#
# Proxy config source (checked in order):
#   1. /mnt/proxy-config/ volume (real K8s secret)
#   2. Env vars: PROXY_NUGET_URL, PROXY_NUGET_USERNAME, PROXY_NUGET_PASSWORD
#   3. Neither → no-op path
#
# Optional env vars:
#   BUILDER — override builder image (default: gcr.io/buildpacks/builder:google-22)
# =============================================================================

echo "========================================"
echo "  E2E pack build — NuGet Proxy Flow"
echo "========================================"

# ── Detect container runtime ─────────────────────────────────────────────────
if [ -S /var/run/docker.sock ]; then
  echo "Runtime: Docker (socket mount)"
  RUNTIME="docker"
elif command -v podman >/dev/null 2>&1; then
  echo "Runtime: podman"
  RUNTIME="podman"
  podman system service -t 0 &
  echo "Waiting for podman socket..."
  RETRIES=0
  while [ $RETRIES -lt 30 ]; do
    if podman info >/dev/null 2>&1; then
      echo "Podman ready after ${RETRIES}s"
      break
    fi
    sleep 1
    RETRIES=$((RETRIES + 1))
  done
  if ! podman info >/dev/null 2>&1; then
    echo "ERROR: Podman failed to start after 30s"
    exit 1
  fi
  export DOCKER_HOST="unix:///run/podman/podman.sock"
else
  echo "ERROR: No container runtime found"
  echo "  Local:   mount Docker socket with -v /var/run/docker.sock:/var/run/docker.sock"
  echo "  Cluster: use privileged pod with podman"
  exit 1
fi

# ── Prepare proxy config dir ─────────────────────────────────────────────────
if [ -d /mnt/proxy-config ] && [ "$(ls -A /mnt/proxy-config 2>/dev/null)" ]; then
  echo "Proxy source: /mnt/proxy-config (K8s secret)"
elif [ -n "$PROXY_NUGET_URL" ]; then
  echo "Proxy source: environment variables"
  mkdir -p /mnt/proxy-config
  printf "%s" "$PROXY_NUGET_URL" > /mnt/proxy-config/pkg-nuget-url
  [ -n "$PROXY_NUGET_USERNAME" ] && printf "%s" "$PROXY_NUGET_USERNAME" > /mnt/proxy-config/pkg-nuget-username
  [ -n "$PROXY_NUGET_PASSWORD" ] && printf "%s" "$PROXY_NUGET_PASSWORD" > /mnt/proxy-config/pkg-nuget-password
  echo "  pkg-nuget-url      = $PROXY_NUGET_URL"
  echo "  pkg-nuget-username = ${PROXY_NUGET_USERNAME:-(not set)}"
else
  echo "Proxy source: none (testing no-op path)"
  mkdir -p /mnt/proxy-config
fi

# ═════════════════════════════════════════════════════════════════════════════
# EXACT shell functions from workflow-resources.ts
# ═════════════════════════════════════════════════════════════════════════════

_PROXY_DIR="/mnt/proxy-config"

_proxy_val() {
  local strategy="$1" key="$2" val=""
  [ -n "$strategy" ] && [ -f "$_PROXY_DIR/${strategy}.${key}" ] && val=$(cat "$_PROXY_DIR/${strategy}.${key}" | tr -d '\n')
  [ -z "$val" ] && [ -f "$_PROXY_DIR/${key}" ] && val=$(cat "$_PROXY_DIR/${key}" | tr -d '\n')
  echo "$val"
}

_resolve_image() {
  local strategy="$1" img_key="$2" oci_key="$3" original="$4"
  local override=$(_proxy_val "$strategy" "$img_key")
  if [ -n "$override" ]; then
    local _basename="${override##*/}"
    if [ "$_basename" = "${_basename%:*}" ] && [ "$_basename" = "${_basename%@*}" ]; then
      if echo "$original" | grep -q '@sha256:'; then
        echo "${override}@${original##*@}"
      elif echo "$original" | grep -q ':'; then
        echo "${override}:${original##*:}"
      else
        echo "$override"
      fi
    else
      echo "$override"
    fi
    return
  fi
  local mirror=$(_proxy_val "$strategy" "$oci_key")
  if [ -n "$mirror" ]; then
    echo "$mirror/${original#*/}"
    return
  fi
  echo "$original"
}

_proxy_login() {
  local strategy="$1"
  for mirror in dockerhub choreo buildpacks; do
    local url=$(_proxy_val "$strategy" "oci-${mirror}-url")
    local user=$(_proxy_val "$strategy" "oci-${mirror}-username")
    local pass=$(_proxy_val "$strategy" "oci-${mirror}-password")
    if [ -n "$url" ] && [ -n "$user" ]; then
      echo "Logging into proxy mirror: ${url%%/*}"
      $RUNTIME login "${url%%/*}" -u "$user" -p "$pass"
    fi
  done
}

_setup_nuget_proxy() {
  local strategy="$1"
  local url=$(_proxy_val "$strategy" pkg-nuget-url)
  [ -z "$url" ] && return
  local user=$(_proxy_val "$strategy" pkg-nuget-username)
  local pass=$(_proxy_val "$strategy" pkg-nuget-password)
  mkdir -p /tmp/nuget-proxy-config
  if [ -n "$user" ]; then
    cat > /tmp/nuget-proxy-config/NuGet.Config <<NGEOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="proxy-mirror" value="${url}" />
  </packageSources>
  <packageSourceCredentials>
    <proxy-mirror>
      <add key="Username" value="${user}" />
      <add key="ClearTextPassword" value="${pass}" />
    </proxy-mirror>
  </packageSourceCredentials>
</configuration>
NGEOF
  else
    cat > /tmp/nuget-proxy-config/NuGet.Config <<NGEOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="proxy-mirror" value="${url}" />
  </packageSources>
</configuration>
NGEOF
  fi
  _LANG_VOLUMES="$_LANG_VOLUMES --volume /tmp/nuget-proxy-config/NuGet.Config:/workspace/NuGet.Config"
}

# ═════════════════════════════════════════════════════════════════════════════
# Execute flow (same order as buildpack-build.ts scriptSource)
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Proxy login ─────────────────────────────────────────────"
_proxy_login buildpack

echo ""
echo "── Initialize variables ────────────────────────────────────"
_LANG_ENV=""
_LANG_VOLUMES=""
_MAVEN_BINDING=""

echo ""
echo "── _setup_nuget_proxy buildpack ────────────────────────────"
_setup_nuget_proxy buildpack

echo "_LANG_ENV      = '$_LANG_ENV'"
echo "_LANG_VOLUMES  = '$_LANG_VOLUMES'"
echo "_MAVEN_BINDING = '$_MAVEN_BINDING'"

if [ -f /tmp/nuget-proxy-config/NuGet.Config ]; then
  echo ""
  echo "Generated NuGet.Config:"
  echo "---"
  cat /tmp/nuget-proxy-config/NuGet.Config
  echo "---"
else
  echo "(No NuGet.Config — no-op path)"
fi

# ── pack build ───────────────────────────────────────────────────────────────
echo ""
echo "── pack build ──────────────────────────────────────────────"

IMAGE="nuget-proxy-e2e-test"
# Google buildpacks builder (same as Choreo uses: gcr.io/buildpacks/builder:google-22)
# Override with BUILDER env var if needed (e.g., for private registry mirror)
BUILDER="${BUILDER:-gcr.io/buildpacks/builder:google-22}"
fullPath="/workspace/app"

# --docker-host=inherit only for podman; for Docker socket, pack finds it automatically
DOCKER_HOST_FLAG=""
[ "$RUNTIME" = "podman" ] && DOCKER_HOST_FLAG="--docker-host=inherit"

BUILD_CMD="pack build $IMAGE $DOCKER_HOST_FLAG --builder $BUILDER --path $fullPath $_LANG_ENV $_LANG_VOLUMES $_MAVEN_BINDING --pull-policy if-not-present --trust-builder"

echo "Command:"
echo "  $BUILD_CMD"
echo ""
eval $BUILD_CMD

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "── Verify built image ──────────────────────────────────────"
$RUNTIME run --rm "$IMAGE"

# ── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────"
$RUNTIME rmi "$IMAGE" 2>/dev/null || true

echo ""
echo "========================================"
if [ -f /tmp/nuget-proxy-config/NuGet.Config ]; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
