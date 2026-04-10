#!/bin/sh
set -e

# =============================================================================
# E2E test of Test Runner proxy flow with actual podman build.
# Replicates the Choreo test runner build flow from test-runner-build.ts:
#   - Conditionally performs Docker Hub login (skipped when proxy is configured)
#   - OCI image resolution via _resolve_image() with strategy "test-runner"
#   - One image: Node.js (resolved via oci-dockerhub-url)
#   - Registry login via _proxy_login test-runner
#   - npm proxy via --build-arg NPM_REGISTRY + --secret id=npmrc
#   - podman build with resolved Node image
#
# VERSION: 0.1.0 — credentials come exclusively from K8s Secret volume mount
# at /mnt/proxy-config/. No env-var shims. Includes conditional Docker Hub
# login matching test-runner-build.ts for restricted/airgapped clusters.
#
# Sample app: Postman collection (based on wso2/choreo-samples/test-runner-postman)
#   - Dockerfile matches generated output from test-runner.service.ts
#   - Installs newman CLI via npm
#   - Copies Postman collection JSON files
#
# Key differences from other tests:
#   - Strategy is "test-runner" (not "buildpack" or "prism")
#   - Uses podman build (not pack build)
#   - One image: Node.js from Docker Hub (via oci-dockerhub-url, not oci-choreo-url)
#   - npm proxy via --build-arg NPM_REGISTRY + --secret id=npmrc (BuildKit)
#   - Only Postman test runner type supported
#
# Skipped (not proxy-related):
#   - podman save to tar
#   - DOCKER_REGISTRY / DOCKER_USER_NAME / DOCKER_USER_PASSWORD env vars
#   - run-collections.sh execution
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
#   oci-dockerhub-url      — Docker Hub mirror host (for Node image)
#   oci-dockerhub-username — Docker Hub mirror username
#   oci-dockerhub-password — Docker Hub mirror password
#   pkg-npm-url            — npm registry proxy URL
#   pkg-npm-token          — npm auth token
#
# Image resolution (matching test-runner-build.ts):
#   Default: node:18-alpine (Docker Hub).
#   _resolve_image rewrites via oci-dockerhub-url from the K8s Secret.
#
# Test scenarios:
#   1. No-proxy (Docker Hub)    — default node:18-alpine, no npm proxy
#   2. OCI mirror (fake URL)    — _resolve_image rewrites node image
#   3. OCI mirror + auth        — _proxy_login test-runner + image resolution
#   4. npm proxy (fake URL)     — --build-arg NPM_REGISTRY set
#   5. npm proxy + auth         — NPM_REGISTRY + --secret id=npmrc
# =============================================================================

echo "========================================"
echo "  E2E podman build — Test Runner Proxy"
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
# Execute flow (same order as test-runner-build.ts scriptSource lines 60-81)
# Strategy: "test-runner"
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Docker Hub login (matching test-runner-build.ts production) ──"
# Skip Docker Hub login when a dockerhub proxy mirror is configured.
# This is the fix for restricted/airgapped clusters where index.docker.io
# is blocked — the original test-runner-build.ts always ran this login
# unconditionally, causing builds to fail before reaching the proxy logic.
if [ -z "$(_proxy_val test-runner oci-dockerhub-url)" ]; then
  echo "No dockerhub proxy configured — logging into Docker Hub"
  if [ -n "$DOCKER_USER_NAME" ] && [ -n "$DOCKER_USER_PASSWORD" ]; then
    $RUNTIME login "${DOCKER_REGISTRY:-https://index.docker.io/v1/}" -u "$DOCKER_USER_NAME" -p "$DOCKER_USER_PASSWORD"
  else
    echo "  DOCKER_USER_NAME/PASSWORD not set — skipping (test mode)"
  fi
else
  echo "Dockerhub proxy configured — skipping Docker Hub login"
fi

echo ""
echo "── Proxy login ─────────────────────────────────────────────"
_proxy_login test-runner

echo ""
echo "── Resolve images via _resolve_image ─────────────────────"

# Default: node:18-alpine from Docker Hub.
# _resolve_image rewrites via oci-dockerhub-url from the K8s Secret.
_NODE_DEFAULT="node:18-alpine"
_NODE_IMAGE=$(_resolve_image test-runner image-node-ref oci-dockerhub-url "$_NODE_DEFAULT")

echo "  _NODE_DEFAULT  = $_NODE_DEFAULT"
echo "  _NODE_IMAGE    = $_NODE_IMAGE"

# ── npm proxy setup ─────────────────────────────────────────────────────────
echo ""
echo "── npm proxy setup ──────────────────────────────────────────"

_NPM_URL=$(_proxy_val test-runner pkg-npm-url)
_NPM_TOKEN=$(_proxy_val test-runner pkg-npm-token)

echo "  _NPM_URL   = ${_NPM_URL:-(not set)}"
echo "  _NPM_TOKEN = $([ -n "$_NPM_TOKEN" ] && echo "****" || echo "(not set)")"

# ── Build conditional --build-arg flags ──────────────────────────────────────
echo ""
echo "── Build conditional --build-arg flags ───────────────────────"

_BUILD_ARGS=""
[ "$_NODE_IMAGE" != "$_NODE_DEFAULT" ] && _BUILD_ARGS="$_BUILD_ARGS --build-arg NODE_IMAGE=$_NODE_IMAGE"
[ -n "$_NPM_URL" ] && _BUILD_ARGS="$_BUILD_ARGS --build-arg NPM_REGISTRY=$_NPM_URL"

# .npmrc generation for authenticated npm proxies (matching test-runner-build.ts lines 74-79)
touch /tmp/.npmrc
if [ -n "$_NPM_TOKEN" ] && [ -n "$_NPM_URL" ]; then
  _NPM_NOSCHEME="${_NPM_URL#*://}"
  _NPM_HOST="${_NPM_NOSCHEME%%/*}"
  echo "//${_NPM_HOST}/:_authToken=${_NPM_TOKEN}" > /tmp/.npmrc
  _BUILD_ARGS="$_BUILD_ARGS --secret id=npmrc,src=/tmp/.npmrc"
  echo "  Generated /tmp/.npmrc for host: $_NPM_HOST"
fi

echo "  _BUILD_ARGS = $_BUILD_ARGS"

# ── podman build ─────────────────────────────────────────────────────────────
echo ""
echo "── podman build ──────────────────────────────────────────────"

BUILD_CMD="$RUNTIME build $_BUILD_ARGS -t choreo/app-image:latest --file /workspace/app/Dockerfile /workspace/app"

echo "Command:"
echo "  $BUILD_CMD"
echo ""
eval $BUILD_CMD

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "── Verify result ─────────────────────────────────────────────"
$RUNTIME image inspect choreo/app-image:latest > /dev/null 2>&1 && echo "Image 'choreo/app-image:latest' built successfully" || { echo "ERROR: Image 'choreo/app-image:latest' not found"; exit 1; }

# ── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────"
$RUNTIME rmi choreo/app-image:latest 2>/dev/null || true

echo ""
echo "========================================"
echo "  E2E TEST PASSED (test-runner, $RUNTIME)"
echo "========================================"
