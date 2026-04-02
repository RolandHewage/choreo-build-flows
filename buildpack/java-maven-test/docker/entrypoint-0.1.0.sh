#!/bin/sh
set -e

# =============================================================================
# E2E test of buildpack Maven proxy flow with actual pack build.
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
#   If empty or missing — no-op path (no proxy, Maven Central used directly)
#
# K8s Secret keys:
#   oci-buildpacks-url      — ACR registry host (e.g., choreoprivateacr.azurecr.io)
#   oci-buildpacks-username — ACR username
#   oci-buildpacks-password — ACR password
#   pkg-maven-url           — Maven proxy URL (optional, e.g., https://nexus.example.com/repository/maven-proxy/)
#   pkg-maven-username      — Maven proxy username (optional, for authenticated proxies)
#   pkg-maven-password      — Maven proxy password (optional, for authenticated proxies)
#
# Image resolution (matching buildpack-build.ts):
#   Original images use choreoprivateacr.azurecr.io (PDP default).
#   _resolve_image rewrites them via oci-buildpacks-url from the K8s Secret.
#
# Maven proxy:
#   When pkg-maven-url is set, a settings.xml is generated with a <mirror>
#   that redirects all Maven downloads (*) to the proxy URL.
#   When pkg-maven-username/password are set, <servers> section is added.
#   The settings.xml is volume-mounted into the build container and passed
#   via GOOGLE_BUILD_ARGS=--settings=<path>.
#
#   NOTE: Google buildpacks do NOT support CNB service bindings.
#   The google.java.maven buildpack uses GOOGLE_BUILD_ARGS to append
#   extra arguments to the mvn command. This is different from Paketo
#   buildpacks which use /platform/bindings/<name>/type + settings.xml.
# =============================================================================

echo "========================================"
echo "  E2E pack build — Maven Proxy Flow"
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
# Maven proxy setup — Google buildpacks use GOOGLE_BUILD_ARGS, NOT CNB bindings
# ═════════════════════════════════════════════════════════════════════════════

_setup_maven_proxy() {
  local strategy="$1"
  local url=$(_proxy_val "$strategy" pkg-maven-url)
  [ -z "$url" ] && return
  local user=$(_proxy_val "$strategy" pkg-maven-username)
  local pass=$(_proxy_val "$strategy" pkg-maven-password)
  mkdir -p /tmp/maven-settings
  cat > /tmp/maven-settings/settings.xml <<MVNEOF
<?xml version="1.0" encoding="UTF-8"?>
<settings>
  <mirrors>
    <mirror>
      <id>proxy-mirror</id>
      <mirrorOf>*</mirrorOf>
      <url>${url}</url>
    </mirror>
  </mirrors>
$(if [ -n "$user" ]; then
cat <<AUTHEOF
  <servers>
    <server>
      <id>proxy-mirror</id>
      <username>${user}</username>
      <password>${pass}</password>
    </server>
  </servers>
AUTHEOF
fi)
</settings>
MVNEOF
  # Mount settings.xml into build container and tell Google Maven buildpack to use it
  _MAVEN_BINDING="--volume /tmp/maven-settings/settings.xml:/maven-settings/settings.xml"
  _LANG_ENV="$_LANG_ENV --env GOOGLE_BUILD_ARGS=--settings=/maven-settings/settings.xml"
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
echo "── _setup_maven_proxy buildpack ────────────────────────────"
_setup_maven_proxy buildpack

echo "_LANG_ENV      = '$_LANG_ENV'"
echo "_LANG_VOLUMES  = '$_LANG_VOLUMES'"
echo "_MAVEN_BINDING = '$_MAVEN_BINDING'"

# Show settings.xml if generated (mask password)
if [ -f /tmp/maven-settings/settings.xml ]; then
  echo ""
  echo "── Generated settings.xml ──────────────────────────────────"
  sed 's|<password>.*</password>|<password>****</password>|' /tmp/maven-settings/settings.xml | sed 's/^/    /'
fi

# ── pack build ───────────────────────────────────────────────────────────────
echo ""
echo "── pack build ──────────────────────────────────────────────"

IMAGE="maven-proxy-e2e-test"
fullPath="/workspace/app"

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
if [ -n "$_MAVEN_BINDING" ]; then
  echo "  E2E TEST PASSED (proxy mode, $RUNTIME)"
else
  echo "  E2E TEST PASSED (no-proxy mode, $RUNTIME)"
fi
echo "========================================"
