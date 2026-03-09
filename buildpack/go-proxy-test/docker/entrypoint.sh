#!/bin/sh
set -e

# =============================================================================
# E2E test of buildpack Go module proxy flow with actual pack build.
# Uses Google buildpacks builder via private ACR mirror
# (choreoprivateacr.azurecr.io/buildpacks/builder:google-22)
#
# VERSION: 0.1.0 — credentials come exclusively from K8s Secret volume mount
# at /mnt/proxy-config/. No env-var shims. Includes .netrc auth for Go proxy.
#
# Two runtime modes (auto-detected):
#   LOCAL   — Docker socket mounted at /var/run/docker.sock
#   CLUSTER — podman running in privileged pod
#
# Proxy config source:
#   /mnt/proxy-config/ volume (K8s Secret mount)
#   If empty or missing — no-op path (no proxy, proxy.golang.org used directly)
#
# K8s Secret keys:
#   oci-buildpacks-url      — ACR registry host (e.g., choreoprivateacr.azurecr.io)
#   oci-buildpacks-username — ACR username
#   oci-buildpacks-password — ACR password
#   pkg-go-url              — Go module proxy URL (optional, e.g., https://nexus.example.com/repository/go-proxy/)
#   pkg-go-username         — Go proxy username (optional, for authenticated proxies)
#   pkg-go-password         — Go proxy password (optional, for authenticated proxies)
#
# Image resolution (matching buildpack-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-buildpacks-url from the K8s Secret.
#
# Go proxy auth:
#   When pkg-go-username/password are set, a .netrc file is generated and
#   mounted into the build container at /home/cnb/.netrc. GONOSUMDB=* is set
#   to skip checksum database verification (sum.golang.org) for all modules.
#   Matching buildpack-build.ts Go section.
# =============================================================================

echo "========================================"
echo "  E2E pack build — Go Module Proxy Flow"
echo "  v0.1.0 (K8s Secret mount + .netrc auth)"
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
# Go module proxy setup (matching buildpack-build.ts Go section)
# ═════════════════════════════════════════════════════════════════════════════

_setup_go_proxy() {
  local strategy="$1"
  _V=$(_proxy_val "$strategy" pkg-go-url)
  if [ -n "$_V" ]; then
    _LANG_ENV="$_LANG_ENV --env GOPROXY=$_V"
    _GO_USER=$(_proxy_val "$strategy" pkg-go-username)
    _GO_PASS=$(_proxy_val "$strategy" pkg-go-password)
    if [ -n "$_GO_USER" ]; then
      _NOSCHEME="${_V#*://}"
      _HOST="${_NOSCHEME%%/*}"
      mkdir -p /tmp/go-proxy-auth
      printf "machine %s\nlogin %s\npassword %s\n" "$_HOST" "$_GO_USER" "$_GO_PASS" > /tmp/go-proxy-auth/.netrc
      _LANG_VOLUMES="$_LANG_VOLUMES --volume /tmp/go-proxy-auth/.netrc:/home/cnb/.netrc"
      _LANG_ENV="$_LANG_ENV --env GONOSUMDB=*"
    fi
  fi
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
echo "── _setup_go_proxy buildpack ──────────────────────────────"
_setup_go_proxy buildpack

echo "_LANG_ENV      = '$_LANG_ENV'"
echo "_LANG_VOLUMES  = '$_LANG_VOLUMES'"
echo "_MAVEN_BINDING = '$_MAVEN_BINDING'"

# Show .netrc if generated (mask password)
if [ -f /tmp/go-proxy-auth/.netrc ]; then
  echo ""
  echo "── .netrc generated ────────────────────────────────────────"
  echo "  File: /tmp/go-proxy-auth/.netrc"
  echo "  Content (password masked):"
  sed 's/password .*/password ****/' /tmp/go-proxy-auth/.netrc | sed 's/^/    /'
fi

# ── pack build ───────────────────────────────────────────────────────────────
echo ""
echo "── pack build ──────────────────────────────────────────────"

IMAGE="go-proxy-e2e-test"
fullPath="/workspace/app"

# Original images — PDP defaults (choreoprivateacr.azurecr.io).
# _resolve_image will rewrite these via oci-buildpacks-url from the K8s Secret.
# (matches buildpack-build.ts lines 182-184)
_ORIGINAL_RUN_IMAGE="choreoprivateacr.azurecr.io/buildpacks/google-22/run:2941124e39ef19f49aabac4257daf5f652805e81"
_ORIGINAL_BUILDER="choreoprivateacr.azurecr.io/buildpacks/builder:google-22"

echo ""
echo "── Resolve images via _resolve_image ─────────────────────"
_RUN_IMAGE=$(_resolve_image buildpack image-buildpacks-run-ref oci-buildpacks-url "$_ORIGINAL_RUN_IMAGE")
_BUILDER_IMAGE=$(_resolve_image buildpack image-buildpacks-builder-ref oci-buildpacks-url "$_ORIGINAL_BUILDER")

echo "  Original run image : $_ORIGINAL_RUN_IMAGE"
echo "  Resolved run image : $_RUN_IMAGE"
echo "  Original builder   : $_ORIGINAL_BUILDER"
echo "  Resolved builder   : $_BUILDER_IMAGE"

# --docker-host=inherit only for podman; for Docker socket, pack finds it automatically
DOCKER_HOST_FLAG=""
[ "$RUNTIME" = "podman" ] && DOCKER_HOST_FLAG="--docker-host=inherit"

BUILD_CMD="pack build $IMAGE $DOCKER_HOST_FLAG --builder \"$_BUILDER_IMAGE\" --run-image=\"$_RUN_IMAGE\" --path $fullPath $_LANG_ENV $_LANG_VOLUMES $_MAVEN_BINDING --pull-policy if-not-present --trust-builder"

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
if echo "$_LANG_ENV" | grep -q "GOPROXY"; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
