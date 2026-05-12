#!/bin/sh
# =============================================================================
# Storage conf race reproducer for Choreo webapp build flow.
#
# Writes /etc/containers/storage.conf in one of two variants, then runs
# `podman build` ITERATIONS times, recording pass / fail count and which
# vite/Rollup imports failed.
#
# Variants:
#   STORAGE_CONF_VARIANT=broken (default)
#     The exact 4-line storage.conf that choreodp-cicd@739a0135 introduced
#     into webapp-build.ts and which produced LATA's intermittent build
#     failures (issue #39296). NO [storage.options.overlay] block.
#
#   STORAGE_CONF_VARIANT=fixed
#     The storage.conf produced by PR #2538 — adds [storage.options] and
#     [storage.options.overlay] with mountopt = "nodev". Mirrors the upstream
#     fix exactly.
#
# Tunables:
#   ITERATIONS              How many podman builds to run.        Default: 20
#   STOP_ON_FAIL=1          Abort the loop on first failure.      Default: 0
#
# Outputs a summary table to stdout and a per-iteration log to /tmp/build-N.log.
# Exits 0 if no failures, 1 otherwise (so cluster Job semantics work).
#
# The race is probabilistic. A "fixed" run that passes once does NOT prove the
# fix; what matters is the failure RATE delta between broken and fixed across
# many iterations. Run both variants back-to-back on the same node to compare.
# =============================================================================
set -u

VARIANT="${STORAGE_CONF_VARIANT:-broken}"
ITERATIONS="${ITERATIONS:-20}"
STOP_ON_FAIL="${STOP_ON_FAIL:-0}"

write_storage_conf() {
  case "$VARIANT" in
    broken)
      cat > /etc/containers/storage.conf <<'STORAGEEOF'
[storage]
driver = "overlay"
graphroot = "/var/lib/containers/storage"
runroot = "/run/containers/storage"
STORAGEEOF
      ;;
    fixed)
      cat > /etc/containers/storage.conf <<'STORAGEEOF'
[storage]
driver = "overlay"
graphroot = "/var/lib/containers/storage"
runroot = "/run/containers/storage"

[storage.options]
additionalimagestores = []

[storage.options.overlay]
mountopt = "nodev"
mount_program = "/usr/bin/fuse-overlayfs"
STORAGEEOF
      ;;
    *)
      echo "ERROR: STORAGE_CONF_VARIANT must be 'broken' or 'fixed' (got: $VARIANT)" >&2
      exit 2
      ;;
  esac
}

echo "================================================================"
echo "  Storage conf race reproducer"
echo "  Variant:    $VARIANT"
echo "  Iterations: $ITERATIONS"
echo "================================================================"

write_storage_conf
echo "── /etc/containers/storage.conf ────────────────────────────────"
cat /etc/containers/storage.conf
echo "────────────────────────────────────────────────────────────────"

# Empty npmrc — the production build mounts it as a BuildKit secret.
touch /tmp/.npmrc

PASS=0
FAIL=0
FAIL_DETAILS=""

i=1
while [ "$i" -le "$ITERATIONS" ]; do
  LOGFILE="/tmp/build-$i.log"
  echo ""
  echo "── Iteration $i / $ITERATIONS ──────────────────────────────────"
  # Fresh storage root every iteration to recreate the cold-pull condition.
  rm -rf /var/lib/containers/storage /run/containers/storage
  mkdir -p /var/lib/containers/storage /run/containers/storage

  if DOCKER_BUILDKIT=1 podman build \
      --secret id=npmrc,src=/tmp/.npmrc \
      -t "choreo/app-image:iter-$i" \
      --file /workspace/app/Dockerfile \
      /workspace/app > "$LOGFILE" 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS (log: $LOGFILE)"
  else
    FAIL=$((FAIL + 1))
    # Pull out the Rollup resolve-import error if present.
    ROLLUP_ERR=$(grep -E "Rollup failed to resolve import|EINTEGRITY|EACCES|ENOENT" "$LOGFILE" | head -3)
    if [ -n "$ROLLUP_ERR" ]; then
      echo "  FAIL — $ROLLUP_ERR"
      FAIL_DETAILS="$FAIL_DETAILS\n  iter $i: $ROLLUP_ERR"
    else
      echo "  FAIL (see $LOGFILE for unrecognised failure)"
      FAIL_DETAILS="$FAIL_DETAILS\n  iter $i: (see $LOGFILE)"
    fi
    if [ "$STOP_ON_FAIL" = "1" ]; then
      echo ""
      echo "STOP_ON_FAIL=1 — aborting loop"
      break
    fi
  fi
  podman rmi "choreo/app-image:iter-$i" 2>/dev/null || true
  i=$((i + 1))
done

echo ""
echo "================================================================"
echo "  Summary — $VARIANT"
echo "================================================================"
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  Failures:%b\n' "$FAIL_DETAILS"
fi
echo "================================================================"

[ "$FAIL" -eq 0 ]
