#!/bin/sh
set -e

# =============================================================================
# E2E test of buildpack Bundler proxy flow with actual pack build.
# Uses Google buildpacks builder via private ACR mirror
# (choreoprivateacr.azurecr.io/buildpacks/builder:google-22)
#
# VERSION: 0.1.0
#
# Two runtime modes (auto-detected):
#   LOCAL   — Docker socket mounted at /var/run/docker.sock
#   CLUSTER — podman running in privileged pod
#
# Proxy config source:
#   /mnt/proxy-config/ volume (K8s Secret mount)
#   If empty or missing — no-op path (no proxy, rubygems.org used directly)
#
# K8s Secret keys:
#   oci-buildpacks-url        — ACR registry host (e.g., choreoprivateacr.azurecr.io)
#   oci-buildpacks-username   — ACR username
#   oci-buildpacks-password   — ACR password
#   pkg-rubygems-url          — RubyGems proxy URL (optional, e.g., https://nexus.example.com/repository/rubygems-proxy/)
#   pkg-rubygems-username     — RubyGems proxy username (optional, for authenticated proxies)
#   pkg-rubygems-password     — RubyGems proxy password (optional, for authenticated proxies)
#
# Image resolution (matching buildpack-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-buildpacks-url from the K8s Secret.
#
# Bundler proxy:
#   When pkg-rubygems-url is set, the Gemfile source URL is replaced from
#   https://rubygems.org to the proxy URL using sed. This approach is needed
#   because the Google Cloud Buildpacks Ruby builder explicitly deletes
#   .bundle/ before running bundle install (confirmed in source code:
#   cmd/ruby/bundle/lib/lib.go — ctx.RemoveAll(".bundle")).
#   For authentication, BUNDLE_<HOST> env var is passed via pack build --env.
#   Bundler reads credentials from BUNDLE_ prefixed env vars automatically.
# =============================================================================

echo "========================================"
echo "  E2E pack build — Bundler Proxy Flow"
echo "  v0.1.0"
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
  export DOCKER_API_VERSION=1.44
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
# Bundler proxy setup (matching buildpack-build.ts inline approach)
# Google buildpack deletes .bundle/ before bundle install, so we modify
# the Gemfile source URL directly + auth via BUNDLE_<HOST> env var
# ═════════════════════════════════════════════════════════════════════════════

_setup_bundler_proxy() {
  local strategy="$1" src_path="$2"
  local url=$(_proxy_val "$strategy" pkg-rubygems-url)
  [ -z "$url" ] && return
  local user=$(_proxy_val "$strategy" pkg-rubygems-username)
  local pass=$(_proxy_val "$strategy" pkg-rubygems-password)

  # Replace rubygems.org source URL in Gemfile with proxy URL
  local gemfile="$src_path/Gemfile"
  if [ -f "$gemfile" ]; then
    echo "  Replacing rubygems.org source in Gemfile with proxy URL..."
    echo "  Before:"
    cat "$gemfile" | sed 's/^/    /'
    local tmp=$(mktemp)
    sed "s|https://rubygems.org[/]*|$url|g" "$gemfile" > "$tmp"
    mv "$tmp" "$gemfile"
    echo "  After:"
    cat "$gemfile" | sed 's/^/    /'
  fi

  # Add credentials via BUNDLE_<HOST> env var
  # Bundler reads BUNDLE_ prefixed env vars for host credentials
  # Key format: BUNDLE_ + uppercase hostname with dots→__ dashes→___
  if [ -n "$user" ]; then
    local _noscheme="${url#*://}"
    local _host="${_noscheme%%/*}"
    _BUNDLE_HOST=$(echo "$_host" | sed 's/\./__/g; s/-/___/g' | tr '[:lower:]' '[:upper:]')
    _LANG_ENV="$_LANG_ENV --env BUNDLE_${_BUNDLE_HOST}=${user}:${pass}"
    echo "  Added credentials for $_host via BUNDLE_${_BUNDLE_HOST} env var (password masked)"
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
IMAGE="bundler-proxy-e2e-test"
fullPath="/workspace/app"

echo ""
echo "── _setup_bundler_proxy buildpack ─────────────────────────"
_setup_bundler_proxy buildpack "$fullPath"

echo "_LANG_ENV      = '$_LANG_ENV'"
echo "_LANG_VOLUMES  = '$_LANG_VOLUMES'"
echo "_MAVEN_BINDING = '$_MAVEN_BINDING'"

# ── pack build ───────────────────────────────────────────────────────────────
echo ""
echo "── pack build ──────────────────────────────────────────────"

# Original images — PDP defaults (choreoprivateacr.azurecr.io).
_ORIGINAL_RUN_IMAGE="choreoprivateacr.azurecr.io/buildpacks/google-22/run:2941124e39ef19f49aabac4257daf5f652805e81"
_ORIGINAL_BUILDER="choreoprivateacr.azurecr.io/buildpacks/builder:google-22"
_ORIGINAL_LIFECYCLE="buildpacksio/lifecycle:0.20.2"

echo ""
echo "── Resolve images via _resolve_image ─────────────────────"
_RUN_IMAGE=$(_resolve_image buildpack image-buildpacks-run-ref oci-buildpacks-url "$_ORIGINAL_RUN_IMAGE")
_BUILDER_IMAGE=$(_resolve_image buildpack image-buildpacks-builder-ref oci-buildpacks-url "$_ORIGINAL_BUILDER")
_LIFECYCLE_IMAGE=$(_resolve_image buildpack image-buildpacks-lifecycle-ref oci-buildpacks-url "$_ORIGINAL_LIFECYCLE")

echo "  Original run image : $_ORIGINAL_RUN_IMAGE"
echo "  Resolved run image : $_RUN_IMAGE"
echo "  Original builder   : $_ORIGINAL_BUILDER"
echo "  Resolved builder   : $_BUILDER_IMAGE"
echo "  Lifecycle image    : $_LIFECYCLE_IMAGE"

# Configure lifecycle image (matching production buildpack-build.ts)
pack config lifecycle-image "$_LIFECYCLE_IMAGE"

# --docker-host=inherit only for podman; for Docker socket, pack finds it automatically
DOCKER_HOST_FLAG=""
[ "$RUNTIME" = "podman" ] && DOCKER_HOST_FLAG="--docker-host=inherit"

BUILD_CMD="pack build $IMAGE $DOCKER_HOST_FLAG --builder \"$_BUILDER_IMAGE\" --run-image=\"$_RUN_IMAGE\" --env DOCKER_API_VERSION=1.44 --path $fullPath $_LANG_ENV $_LANG_VOLUMES $_MAVEN_BINDING --pull-policy if-not-present"

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
if ! grep -q "rubygems.org" "$fullPath/Gemfile" 2>/dev/null; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
