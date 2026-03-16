#!/bin/sh
set -e

# =============================================================================
# E2E test of Prism Mock proxy flow with actual podman build.
# Replicates the Choreo prism build flow from prism-build.ts:
#   - OCI image resolution via _resolve_image() with strategy "prism"
#   - Two images: Prism server + Golang (resolved via oci-choreo-url)
#   - Registry login via _proxy_login prism
#   - npm proxy via _setup_npm_proxy prism (for prism-docker-resource-generator)
#   - podman build with resolved images (simulating generated Dockerfile)
#
# VERSION: 0.1.0 — credentials come exclusively from K8s Secret volume mount
# at /mnt/proxy-config/. No env-var shims.
#
# Sample app: Petstore OpenAPI spec (based on wso2/choreo-samples/prism-mock-service)
#
# Key differences from buildpack tests:
#   - Strategy is "prism" (not "buildpack" or "mi")
#   - Uses podman build (not pack build)
#   - Two managed images: Prism + Golang (via oci-choreo-url, not oci-buildpacks-url)
#   - Has npm proxy via _setup_npm_proxy (for build-time npm install)
#   - No buildpack lifecycle/builder/run images
#
# Skipped (not proxy-related):
#   - prism-docker-resource-generator (node index.js)
#   - Dockerfile generation logic
#   - podman save to tar
#   - Azure CR read-user env vars
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
#   oci-choreo-url         — Choreo ACR mirror host
#   oci-choreo-username    — Choreo ACR mirror username
#   oci-choreo-password    — Choreo ACR mirror password
#   pkg-npm-url            — npm registry proxy URL
#   pkg-npm-token          — npm auth token
#
# Image resolution (matching prism-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-choreo-url from the K8s Secret.
#
# Test scenarios:
#   1. No-proxy (ACR only)      — default prism/golang from ACR, no npm proxy
#   2. OCI mirror (fake URL)    — _resolve_image rewrites prism + golang
#   3. OCI mirror + auth        — _proxy_login prism + image resolution
#   4. npm proxy (fake URL)     — _setup_npm_proxy prism configures registry
#   5. npm proxy + auth         — npm config with authToken
# =============================================================================

echo "========================================"
echo "  E2E podman build — Prism Mock Proxy"
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

# npm proxy function from workflow-resources.ts lines 502-513
_setup_npm_proxy() {
  local strategy="$1"
  local url=$(_proxy_val "$strategy" pkg-npm-url)
  [ -z "$url" ] && return
  local token=$(_proxy_val "$strategy" pkg-npm-token)
  npm config set registry "$url"
  if [ -n "$token" ]; then
    local _noscheme="${url#*://}"
    local host="${_noscheme%%/*}"
    npm config set "//${host}/:_authToken" "$token"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# Execute flow (same order as prism-build.ts scriptSource lines 73-98)
# Strategy: "prism"
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Proxy login ─────────────────────────────────────────────"
_proxy_login prism

echo ""
echo "── Resolve images via _resolve_image ─────────────────────"

# Original images — PDP defaults (choreoprivateacr.azurecr.io).
# _resolve_image will rewrite these via oci-choreo-url from the K8s Secret.
_ORIGINAL_PRISM="choreoprivateacr.azurecr.io/stoplight/prism:5"
_ORIGINAL_GOLANG="choreoprivateacr.azurecr.io/golang:1.22.4-alpine"

_PRISM_IMAGE=$(_resolve_image prism image-prism-ref oci-choreo-url "$_ORIGINAL_PRISM")
_GOLANG_IMAGE=$(_resolve_image prism image-golang-ref oci-choreo-url "$_ORIGINAL_GOLANG")

echo "  Original prism   : $_ORIGINAL_PRISM"
echo "  Resolved prism   : $_PRISM_IMAGE"
echo "  Original golang  : $_ORIGINAL_GOLANG"
echo "  Resolved golang  : $_GOLANG_IMAGE"

# ── npm proxy setup ─────────────────────────────────────────────────────────
echo ""
echo "── npm proxy setup ──────────────────────────────────────────"
_setup_npm_proxy prism

_NPM_REGISTRY=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")
echo "  npm registry: $_NPM_REGISTRY"

# ── Generate Dockerfile (simulating prism-docker-resource-generator) ────────
echo ""
echo "── Generate Dockerfile ──────────────────────────────────────"

mkdir -p /tmp/prism-build
cp -r /workspace/app/specs /tmp/prism-build/

# The prism-docker-resource-generator creates a Dockerfile in ./temp that uses
# CHOREO_MANAGED_PRISM_IMAGE and CHOREO_MANAGED_GOLANG_IMAGE. We simulate this
# by generating a minimal Dockerfile with the resolved images.
cat > /tmp/prism-build/Dockerfile <<EOF
FROM ${_GOLANG_IMAGE} AS builder
RUN echo "Golang build stage verified"

FROM ${_PRISM_IMAGE}
COPY specs/petstore_openapi.yaml /tmp/openapi.yaml
CMD ["mock", "-h", "0.0.0.0", "-p", "4010", "/tmp/openapi.yaml"]
EOF

echo "  Generated Dockerfile:"
cat /tmp/prism-build/Dockerfile

# ── podman build ─────────────────────────────────────────────────────────────
echo ""
echo "── podman build ──────────────────────────────────────────────"

IMAGE="prism-proxy-e2e-test"
BUILD_CMD="$RUNTIME build -t $IMAGE /tmp/prism-build/"

echo "Command:"
echo "  $BUILD_CMD"
echo ""
eval $BUILD_CMD

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "── Verify result ─────────────────────────────────────────────"
$RUNTIME image inspect "$IMAGE" > /dev/null 2>&1 && echo "Image '$IMAGE' built successfully" || { echo "ERROR: Image '$IMAGE' not found"; exit 1; }

# ── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────"
$RUNTIME rmi "$IMAGE" 2>/dev/null || true
rm -rf /tmp/prism-build

echo ""
echo "========================================"
echo "  E2E TEST PASSED (prism, $RUNTIME)"
echo "========================================"
