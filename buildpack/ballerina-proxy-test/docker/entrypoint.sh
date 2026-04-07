#!/bin/sh
set -e

# =============================================================================
# E2E test of Ballerina buildpack proxy flow with actual pack build.
# Uses Choreo custom builder via private ACR mirror
# (choreoprivateacr.azurecr.io/choreoipaas/choreo-buildpacks/builder:0.2.78)
#
# VERSION: 0.1.0 — credentials come exclusively from K8s Secret volume mount
# at /mnt/proxy-config/. No env-var shims.
#
# Key difference from other buildpack tests:
#   - Strategy is "ballerina" (not "buildpack")
#   - Uses `pack config lifecycle-image` before build (explicit lifecycle)
#   - No package manager proxy (Ballerina Central is not proxied)
#   - Only OCI image proxy (lifecycle + builder)
#
# Two runtime modes (auto-detected):
#   LOCAL   — Docker socket mounted at /var/run/docker.sock
#   CLUSTER — podman running in privileged pod
#
# Proxy config source:
#   /mnt/proxy-config/ volume (K8s Secret mount)
#   If empty or missing — no-op path (images used as-is)
#
# K8s Secret keys:
#   oci-buildpacks-url      — ACR registry host (e.g., choreoprivateacr.azurecr.io)
#   oci-buildpacks-username — ACR username
#   oci-buildpacks-password — ACR password
#
# Image resolution (matching ballerina-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-buildpacks-url from the K8s Secret.
#
# Ballerina build env vars (matching ballerina-build.ts):
#   BALLERINA_PROD_CENTRAL=true  — use production Ballerina Central (api.central.ballerina.io)
#   OTHER_BAL_BUILD_ARGS=--cloud=k8s — generate K8s artifacts
#   DISABLE_BAL_OBSERVABILITY=true — disable observability
#   BUILD_PATH=. — build from project root
#   DOCKER_API_VERSION=1.44 — Docker API compatibility
# =============================================================================

echo "========================================"
echo "  E2E pack build — Ballerina Proxy Flow"
echo "  v0.1.0 (K8s Secret mount)"
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

# ── Show proxy config status ─────────────────────────────────────────────────
echo ""
echo "── Proxy config (/mnt/proxy-config/) ─────────────────────"
if [ -d /mnt/proxy-config ] && [ "$(ls -A /mnt/proxy-config 2>/dev/null)" ]; then
  echo "Proxy source: /mnt/proxy-config (K8s Secret mount)"
  echo "Files present:"
  ls -la /mnt/proxy-config/
else
  echo "Proxy source: none (testing no-op path)"
  echo "  /mnt/proxy-config/ is empty or not mounted"
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

# ═════════════════════════════════════════════════════════════════════════════
# Execute flow (same order as ballerina-build.ts scriptSource lines 155-196)
# Strategy: "ballerina" (not "buildpack")
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Proxy login ─────────────────────────────────────────────"
_proxy_login ballerina

echo ""
echo "── Resolve images via _resolve_image ─────────────────────"

# Original images — PDP defaults (choreoprivateacr.azurecr.io).
# _resolve_image will rewrite these via oci-buildpacks-url from the K8s Secret.
# Lifecycle: choreocontrolplane.azurecr.io/buildpacksio/lifecycle:0.19.6 → PDP rewrite
# Builder: choreocontrolplane.azurecr.io/choreoipaas/choreo-buildpacks/builder:0.2.78 → PDP rewrite
_ORIGINAL_LIFECYCLE="choreoprivateacr.azurecr.io/buildpacksio/lifecycle:0.20.2"
_ORIGINAL_BUILDER="choreoprivateacr.azurecr.io/choreoipaas/choreo-buildpacks/builder:0.2.83"
_ORIGINAL_RUN_IMAGE="choreoprivateacr.azurecr.io/choreoipaas/choreo-buildpacks/stacks/alpine/run:0.2.83"

_LIFECYCLE_IMAGE=$(_resolve_image ballerina image-buildpacks-lifecycle-ref oci-buildpacks-url "$_ORIGINAL_LIFECYCLE")
_BUILDER_IMAGE=$(_resolve_image ballerina image-buildpacks-builder-ref oci-buildpacks-url "$_ORIGINAL_BUILDER")
_RUN_IMAGE=$(_resolve_image ballerina image-buildpacks-run-ref oci-buildpacks-url "$_ORIGINAL_RUN_IMAGE")

echo "  Original lifecycle : $_ORIGINAL_LIFECYCLE"
echo "  Resolved lifecycle : $_LIFECYCLE_IMAGE"
echo "  Original builder   : $_ORIGINAL_BUILDER"
echo "  Resolved builder   : $_BUILDER_IMAGE"
echo "  Original run image : $_ORIGINAL_RUN_IMAGE"
echo "  Resolved run image : $_RUN_IMAGE"

# ── pack config lifecycle-image (unique to Ballerina) ─────────────────────
echo ""
echo "── pack config lifecycle-image ───────────────────────────"
echo "  Setting lifecycle image: $_LIFECYCLE_IMAGE"
pack config lifecycle-image "$_LIFECYCLE_IMAGE"

# ── pack build ───────────────────────────────────────────────────────────────
echo ""
echo "── pack build ──────────────────────────────────────────────"

IMAGE="ballerina-proxy-e2e-test"
fullPath="/workspace/app"

mkdir -p "$fullPath/generated-artifacts" "$fullPath/swagger"
# cnb user (UID 1000) needs write access to generated-artifacts
chmod 777 "$fullPath/generated-artifacts"

# --docker-host=inherit only for podman; for Docker socket, pack finds it automatically
DOCKER_HOST_FLAG=""
[ "$RUNTIME" = "podman" ] && DOCKER_HOST_FLAG="--docker-host=inherit"

# Ballerina-specific env vars (matching ballerina-build.ts baseEnvArgs)
# Note: Production uses OTHER_BAL_BUILD_ARGS=--cloud=k8s which triggers the Ballerina
# cloud plugin to run `docker build` for K8s artifacts. This requires docker/podman
# inside the builder container (available in production via podman socket).
# For E2E proxy validation, we skip --cloud=k8s since it's not relevant to proxy flow.
BUILD_CMD="pack build $IMAGE $DOCKER_HOST_FLAG \
  --builder \"$_BUILDER_IMAGE\" \
  --run-image=\"$_RUN_IMAGE\" \
  --path $fullPath \
  --env BALLERINA_PROD_CENTRAL=true \
  --env 'OTHER_BAL_BUILD_ARGS=' \
  --env DISABLE_BAL_OBSERVABILITY=true \
  --env BUILD_PATH=. \
  --env DOCKER_API_VERSION=1.44 \
  --volume \"$fullPath/generated-artifacts\":/app/generated-artifacts:rw \
  --pull-policy if-not-present"

echo "Command:"
echo "  $BUILD_CMD"
echo ""
eval $BUILD_CMD

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "── Verify built image ──────────────────────────────────────"
$RUNTIME image inspect "$IMAGE" > /dev/null 2>&1 && echo "Image '$IMAGE' built successfully" || { echo "ERROR: Image '$IMAGE' not found"; exit 1; }

# ── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────"
$RUNTIME rmi "$IMAGE" 2>/dev/null || true

echo ""
echo "========================================"
echo "  E2E TEST PASSED (ballerina, $RUNTIME)"
echo "========================================"
