# Webapp React — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175677 | none | PASSED |
| With npm proxy | build-and-deploy-20000175681 | pkg-npm-* | PASSED |

## Test 1: No proxy — PASSED

- 1495 packages installed in 15s from default registry
- `missing "NPM_REGISTRY" build argument` warning (expected)
- Node from `docker.io`, nginx from `choreoanonymouspullable.azurecr.io`
- Build succeeded

## Test 2: With npm proxy — PASSED

- 1495 packages installed in 5m through Nexus proxy (ngrok)
- ngrok logs confirmed all traffic routed through proxy (200 OK)
- Build succeeded, image pushed
- Note: Previous attempt (pod 20000175680) failed due to trailing space in secret URL value

## Notes

- Token used: `<nexus-npm-token>` (Nexus npm bearer token)
- Trailing spaces in secret values cause `podman build` arg parsing errors — `_proxy_val` strips newlines but not spaces
