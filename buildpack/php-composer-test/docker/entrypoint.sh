#!/bin/sh
set -e

# =============================================================================
# E2E test of buildpack Composer proxy flow with actual pack build.
# Uses Google buildpacks builder via private ACR mirror
# (choreoprivateacr.azurecr.io/buildpacks/builder:google-22)
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
#   If empty or missing — no-op path (no proxy, packagist.org used directly)
#
# K8s Secret keys:
#   oci-buildpacks-url        — ACR registry host (e.g., choreoprivateacr.azurecr.io)
#   oci-buildpacks-username   — ACR username
#   oci-buildpacks-password   — ACR password
#   pkg-composer-url          — Composer proxy URL (optional, e.g., https://nexus.example.com/repository/composer-proxy/)
#   pkg-composer-username     — Composer proxy username (optional, for authenticated proxies)
#   pkg-composer-password     — Composer proxy password (optional, for authenticated proxies)
#
# Image resolution (matching buildpack-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-buildpacks-url from the K8s Secret.
#
# Composer proxy:
#   When pkg-composer-url is set, the proxy repository is injected
#   directly into the project's composer.json (packagist.org disabled).
#   This avoids volume-mounting to COMPOSER_HOME — pack build volume
#   mounts are read-only for the CNB user, and the buildpack's
#   composer-install step needs to write keys there.
#   When credentials are provided, auth.json is written next to
#   composer.json in the project directory. Composer reads auth.json
#   from the project root automatically. This avoids COMPOSER_AUTH
#   env var (JSON gets mangled by shell eval) and COMPOSER_HOME
#   volume mount issues (read-only for CNB user).
# =============================================================================

echo "========================================"
echo "  E2E pack build — Composer Proxy Flow"
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
# Composer proxy setup (proposed for workflow-resources.ts)
# ═════════════════════════════════════════════════════════════════════════════

_setup_composer_proxy() {
  local strategy="$1" src_path="$2"
  local url=$(_proxy_val "$strategy" pkg-composer-url)
  [ -z "$url" ] && return
  local user=$(_proxy_val "$strategy" pkg-composer-username)
  local pass=$(_proxy_val "$strategy" pkg-composer-password)
  local _noscheme="${url#*://}"
  local _host="${_noscheme%%/*}"

  # Inject proxy repository into the project's composer.json.
  #
  # Why not COMPOSER_HOME/config.json + --volume?
  #   pack build volume mounts are read-only for the CNB user during the
  #   build phase. The Google buildpack's composer-install step writes
  #   keys.dev.pub to COMPOSER_HOME (~/.composer), which fails on a
  #   volume mount. Modifying composer.json avoids this entirely.
  local cjson="$src_path/composer.json"
  if [ -f "$cjson" ]; then
    echo "  Injecting proxy repository into composer.json..."
    local tmp=$(mktemp)
    jq --arg url "$url" \
      '.repositories = [{"type":"composer","url":$url},{"packagist.org":false}] + (.repositories // [])' \
      "$cjson" > "$tmp"
    mv "$tmp" "$cjson"
    echo "  Updated composer.json:"
    cat "$cjson" | sed 's/^/    /'
  fi

  # Authentication via auth.json in project directory.
  # Composer reads auth.json from the project root (next to composer.json).
  # This avoids shell quoting issues with COMPOSER_AUTH env var (JSON gets
  # mangled by eval) and volume mount issues with COMPOSER_HOME (read-only).
  if [ -n "$user" ]; then
    printf '{"http-basic":{"%s":{"username":"%s","password":"%s"}}}' \
      "$_host" "$user" "$pass" > "$src_path/auth.json"
    echo "  Generated auth.json (password masked):"
    sed 's/"password":"[^"]*"/"password":"****"/' "$src_path/auth.json" | sed 's/^/    /'
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
IMAGE="composer-proxy-e2e-test"
fullPath="/workspace/app"

echo ""
echo "── _setup_composer_proxy buildpack ────────────────────────"
_setup_composer_proxy buildpack "$fullPath"

echo "_LANG_ENV      = '$_LANG_ENV'"
echo "_LANG_VOLUMES  = '$_LANG_VOLUMES'"
echo "_MAVEN_BINDING = '$_MAVEN_BINDING'"

# Show auth.json if generated (password already masked during generation)
if [ -f "$fullPath/auth.json" ]; then
  echo ""
  echo "── auth.json present in project directory ──────────────────"
  sed 's/"password":"[^"]*"/"password":"****"/' "$fullPath/auth.json" | sed 's/^/    /'
fi

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
if grep -q "packagist.org" "$fullPath/composer.json" 2>/dev/null && grep -q "false" "$fullPath/composer.json" 2>/dev/null; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
