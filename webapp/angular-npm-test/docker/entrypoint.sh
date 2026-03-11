#!/bin/sh
set -e

# =============================================================================
# E2E test of webapp npm proxy flow with actual podman build (Angular).
# Replicates the Choreo webapp build flow from webapp-build.ts:
#   - Resolves proxy images (node, nginx) via _resolve_image()
#   - Conditionally passes --build-arg flags only when values differ from defaults
#   - Injects .npmrc as Docker build secret for npm token auth
#   - Runs podman build with the generated Dockerfile
#
# VERSION: 0.1.0 — credentials come exclusively from K8s Secret volume mount
# at /mnt/proxy-config/. No env-var shims.
#
# Two runtime modes (auto-detected):
#   LOCAL   — Docker socket mounted at /var/run/docker.sock
#   CLUSTER — podman running in privileged pod
#
# Proxy config source:
#   /mnt/proxy-config/ volume (K8s Secret mount)
#   If empty or missing → no-op path (default images, no registry override)
#
# K8s Secret keys:
#   oci-dockerhub-url      — DockerHub mirror host (for node image)
#   oci-dockerhub-username — DockerHub mirror username
#   oci-dockerhub-password — DockerHub mirror password
#   oci-choreo-url         — Choreo ACR mirror host (for nginx image)
#   oci-choreo-username    — Choreo ACR mirror username
#   oci-choreo-password    — Choreo ACR mirror password
#   pkg-npm-url            — npm registry proxy URL (optional)
#   pkg-npm-token          — npm registry auth token (optional)
#
# Image resolution (matching webapp-build.ts):
#   node:18-alpine → _resolve_image via image-node-ref / oci-dockerhub-url
#   choreoanonymouspullable.azurecr.io/... → _resolve_image via image-nginx-ref / oci-choreo-url
# =============================================================================

echo "========================================"
echo "  E2E podman build — Angular Webapp NPM Proxy"
echo "  v0.1.0 (K8s Secret mount only)"
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
# Execute flow (same order as webapp-build.ts scriptSource lines 67-84)
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Proxy login ─────────────────────────────────────────────"
_proxy_login webapp

echo ""
echo "── Resolve images ────────────────────────────────────────────"
_NODE_DEFAULT="node:18-alpine"
_NODE_IMAGE=$(_resolve_image webapp image-node-ref oci-dockerhub-url "$_NODE_DEFAULT")

_NGINX_DEFAULT="choreoanonymouspullable.azurecr.io/nginxinc/nginx-unprivileged:stable-alpine-slim"
_NGINX_IMAGE=$(_resolve_image webapp image-nginx-ref oci-choreo-url "$_NGINX_DEFAULT")

_NPM_URL=$(_proxy_val webapp pkg-npm-url)
_NPM_TOKEN=$(_proxy_val webapp pkg-npm-token)

echo "  _NODE_DEFAULT  = $_NODE_DEFAULT"
echo "  _NODE_IMAGE    = $_NODE_IMAGE"
echo "  _NGINX_DEFAULT = $_NGINX_DEFAULT"
echo "  _NGINX_IMAGE   = $_NGINX_IMAGE"
echo "  _NPM_URL       = ${_NPM_URL:-(not set)}"
echo "  _NPM_TOKEN     = ${_NPM_TOKEN:+(set)}"

echo ""
echo "── Build conditional --build-arg flags ───────────────────────"
_BUILD_ARGS=""
[ "$_NODE_IMAGE" != "$_NODE_DEFAULT" ] && _BUILD_ARGS="$_BUILD_ARGS --build-arg NODE_IMAGE=$_NODE_IMAGE"
[ "$_NGINX_IMAGE" != "$_NGINX_DEFAULT" ] && _BUILD_ARGS="$_BUILD_ARGS --build-arg NGINX_IMAGE=$_NGINX_IMAGE"
[ -n "$_NPM_URL" ] && _BUILD_ARGS="$_BUILD_ARGS --build-arg NPM_REGISTRY=$_NPM_URL"

# Always create .npmrc and pass as BuildKit secret (empty if no token)
touch /tmp/.npmrc
if [ -n "$_NPM_TOKEN" ] && [ -n "$_NPM_URL" ]; then
  _NPM_NOSCHEME="${_NPM_URL#*://}"
  _NPM_HOST="${_NPM_NOSCHEME%%/*}"
  echo "//${_NPM_HOST}/:_authToken=${_NPM_TOKEN}" > /tmp/.npmrc
  echo "  Generated /tmp/.npmrc for host: $_NPM_HOST"
fi
_BUILD_ARGS="$_BUILD_ARGS --secret id=npmrc,src=/tmp/.npmrc"

echo "  _BUILD_ARGS = $_BUILD_ARGS"

# ── podman build ─────────────────────────────────────────────────────────────
echo ""
echo "── podman build ──────────────────────────────────────────────"

BUILD_CMD="DOCKER_BUILDKIT=1 $RUNTIME build $_BUILD_ARGS -t choreo/app-image:latest --file /workspace/app/Dockerfile /workspace/app"

echo "Command:"
echo "  $BUILD_CMD"
echo ""
eval $BUILD_CMD

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "── Verify built image ──────────────────────────────────────"
$RUNTIME image inspect choreo/app-image:latest > /dev/null 2>&1 && echo "Image 'choreo/app-image:latest' built successfully" || { echo "ERROR: Image 'choreo/app-image:latest' not found"; exit 1; }

# ── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────"
$RUNTIME rmi choreo/app-image:latest 2>/dev/null || true

echo ""
echo "========================================"
if [ -n "$_NPM_URL" ]; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
