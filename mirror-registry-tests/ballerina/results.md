# Ballerina — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175690 | none | PASSED |
| With proxy (oci-choreo-url, fake) | build-and-deploy-20000175689 | oci-choreo-* (fake) | PASSED (build failed as expected) |
| With proxy (oci-buildpacks-url, fake) | build-and-deploy-20000175691 | oci-buildpacks-* (fake) | PASSED (build failed as expected) |
| With proxy (oci-buildpacks-url, real ACR) | build-and-deploy-20000175692 | oci-buildpacks-* (real) | PASSED (build succeeded) |

## Test 1: No proxy — PASSED

- Choreo buildpack `choreoipaas/choreo-buildpacks/builder:0.2.107`
- Lifecycle from `choreocontrolplane.azurecr.io/buildpacksio/lifecycle:0.20.2`
- Run image from `choreocontrolplane.azurecr.io/choreoipaas/choreo-buildpacks/stacks/alpine/run:0.2.107`
- Ballerina deps from `dev-central.ballerina.io` (crypto, cache, constraint, http)
- JDK 17.0.7, Ballerina 2201.8.4
- Build succeeded, JAR + K8s artifacts generated

## Test 2: With proxy (oci-choreo-url, fake) — PASSED

- `Logging into proxy mirror: fake-mirror.example.com` in logs
- Build failed with exit 125 — correct behavior

## Test 3: With proxy (oci-buildpacks-url, fake) — PASSED

- `Logging into proxy mirror: fake-mirror.example.com` in logs
- Build failed with exit 125 — correct behavior

## Test 4: With proxy (oci-buildpacks-url, real ACR credentials) — PASSED

- `Logging into proxy mirror: choreocontrolplane.azurecr.io` → `Login Succeeded!`
- Real ACR credentials used for `oci-buildpacks-url`
- All images pulled successfully: lifecycle, builder, run
- Full Ballerina build completed: JDK, Ballerina, compile, JAR, K8s artifacts
- Image exported and pushed to ACR

## Notes

- Ballerina resolves lifecycle and builder images via `_resolve_image` but NOT the run image (run image is embedded in builder metadata)
- This is a limitation but not a blocking issue — `_proxy_login` authenticates to the mirror, and the run image is on the same registry as the builder
- Ballerina Central packages (`dev-central.ballerina.io`) are not proxied — out of scope for this feature
- JDK/Ballerina distribution downloaded from `dist.ballerina.io` — also not proxied (hardcoded in buildpack)
