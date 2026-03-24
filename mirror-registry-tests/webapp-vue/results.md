# Webapp Vue — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175679 | none | PASSED |
| With npm proxy | build-and-deploy-20000175683 | pkg-npm-* | PASSED |

## Test 1: No proxy — PASSED

- 965 packages installed in 9s from default registry
- `missing "NPM_REGISTRY" build argument` warning (expected)
- `vue-cli-service build` succeeded
- Build succeeded

## Test 2: With npm proxy — PASSED

- 965 packages installed in 53s through Nexus proxy (ngrok)
- ngrok logs confirmed all traffic routed through proxy (200 OK)
- `vue-cli-service build` succeeded
- Build succeeded, image pushed

## Notes

- Same npm proxy pattern as React — `--build-arg NPM_REGISTRY` + `.npmrc` secret mount
- Vue CLI (`vue-cli-service build`) works correctly with proxied npm packages
