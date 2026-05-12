# Storage Conf Race Reproducer — LATA / #39296

E2E reproducer for the intermittent webapp build failure surfaced as
`[vite]: Rollup failed to resolve import "@radix-ui/react-…"` in LATA's
production builds.

The race is in the **podman overlay storage layer**, not the application code.
choreodp-cicd commit 739a0135 narrowed `/etc/containers/storage.conf` from the
argo-docker-build image's default to a 4-line minimal version, dropping
`[storage.options]` and `[storage.options.overlay]` (incl. `mountopt = "nodev"`).
Without those overlay tunings, npm's parallel tarball extraction occasionally
leaves files visible in directory listings before their content is readable.
`npm install` reports a clean install, then vite/Rollup fails to resolve a
random `@radix-ui/*` package from the freshly-extracted tarball tree.

PR [#2538](https://github.com/wso2-enterprise/choreodp-cicd/pull/2538) restores
the overlay options.

## What this test does

1. Writes `/etc/containers/storage.conf` in one of two variants — `broken`
   (reproduces the LATA failure) or `fixed` (PR #2538 storage.conf).
2. Runs `podman build` against `app/` N times in a row, with a fresh
   `graphroot` on each iteration to force cold tarball extraction.
3. Reports pass / fail count and which Rollup imports failed.

The race is **probabilistic**. A single run proves nothing. Run with
`ITERATIONS=50` or higher and compare failure rates between `broken` and
`fixed` on the **same host**.

## Build the test image

```bash
cd docker/
docker build --platform linux/amd64 -t rolandhewage/webapp-storage-race:0.1.0 .
docker push rolandhewage/webapp-storage-race:0.1.0
```

## Run — on a Choreo PDP cluster (closest to production)

Production reproduction. PR #2538 only matters on Linux overlay backends in a
real build pod — this is the only mode that proves the fix.

```bash
kubectl run storage-race-broken --rm -it --restart=Never \
  --image=rolandhewage/webapp-storage-race:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"runner",
        "image":"rolandhewage/webapp-storage-race:0.1.0",
        "imagePullPolicy":"Always",
        "env":[
          {"name":"STORAGE_CONF_VARIANT","value":"broken"},
          {"name":"ITERATIONS","value":"30"}
        ],
        "securityContext":{"privileged":true}
      }]
    }
  }'

kubectl run storage-race-fixed --rm -it --restart=Never \
  --image=rolandhewage/webapp-storage-race:0.1.0 \
  --overrides='{
    "spec":{
      "containers":[{
        "name":"runner",
        "image":"rolandhewage/webapp-storage-race:0.1.0",
        "imagePullPolicy":"Always",
        "env":[
          {"name":"STORAGE_CONF_VARIANT","value":"fixed"},
          {"name":"ITERATIONS","value":"30"}
        ],
        "securityContext":{"privileged":true}
      }]
    }
  }'
```

Run them sequentially on the same node — schedule with a nodeSelector if your
cluster has heterogeneous node pools.

## Run — locally on macOS

Docker Desktop's vfs/overlay backend is **not** the same as AKS overlay-fs.
A `broken` run may pass every iteration locally even with a clearly buggy
storage.conf. Treat local runs as a smoke test of the harness only, not as
fix validation.

```bash
docker run --rm -it --privileged \
  -e STORAGE_CONF_VARIANT=broken -e ITERATIONS=10 \
  rolandhewage/webapp-storage-race:0.1.0

docker run --rm -it --privileged \
  -e STORAGE_CONF_VARIANT=fixed -e ITERATIONS=10 \
  rolandhewage/webapp-storage-race:0.1.0
```

## Tunables

| Env var | Default | Meaning |
|---|---|---|
| `STORAGE_CONF_VARIANT` | `broken` | `broken` (no overlay options) or `fixed` (PR #2538 options) |
| `ITERATIONS` | `20` | How many podman builds per run |
| `STOP_ON_FAIL` | `0` | If `1`, abort the loop on the first failure |

## Interpreting results

| broken | fixed | Verdict |
|---|---|---|
| Fail rate > 0 | Fail rate = 0 | Strong evidence the fix resolves the race |
| Fail rate > 0 | Fail rate > 0 but lower | Partial — there is residual race; investigate PVC backing storage / kernel overlay version |
| Fail rate = 0 | Fail rate = 0 | Inconclusive — race not triggered by this host. Try a different cluster, higher iteration count, or noisier neighbour load |
| Fail rate = 0 | Fail rate > 0 | Surprising — file as a separate bug |

## Caveats

- The customer's LATA webapp has thousands of npm packages; this fixture has ~30
  `@radix-ui/*` packages plus React/Vite. Race amplitude scales with the
  package count and the tarball-size distribution. If you can't reproduce
  `broken` failures with this fixture, copy a real LATA-shaped `package.json`
  into `docker/app/` and rebuild the test image.
- The fix in PR #2538 also restores `mountopt = "nodev"` which is what the
  upstream argo-docker-build storage.conf carried. The test's `fixed` variant
  intentionally includes both `mountopt = "nodev"` and `mount_program =
  "/usr/bin/fuse-overlayfs"` so it works under unprivileged rootless podman
  inside a container. Production webapp builds are privileged pods and use
  kernel overlay, no fuse — that delta is fine for race testing but the test
  cannot 1:1 reproduce kernel-overlay-only behaviour.
- Per the #39296 memory note, the fix is rated ~70% likely to fully resolve
  customer failures. Residual risk lives in the PVC backing storage / kernel
  overlay version on the WSO2 Internal Apps PDP. This test will not detect
  those.

## App shape

```
app/
├── Dockerfile                 # node:18-alpine builder → nginx, matches LATA pattern
├── package.json               # React + Vite + TS + 27 @radix-ui/* packages
├── tsconfig.json
├── vite.config.ts
├── index.html
├── default.conf               # nginx
└── src/
    ├── main.tsx
    ├── App.tsx                # imports each ui component
    └── components/ui/         # one file per radix family — same shape as
        ├── dropdown-menu.tsx  # LATA's "Rollup failed to resolve
        ├── dialog.tsx         # @radix-ui/react-dropdown-menu from
        ├── popover.tsx        # .../components/ui/dropdown-menu.tsx" trail
        ├── select.tsx
        ├── tabs.tsx
        ├── accordion.tsx
        ├── tooltip.tsx
        ├── toast.tsx
        ├── navigation-menu.tsx
        ├── context-menu.tsx
        ├── menubar.tsx
        └── hover-card.tsx
```
