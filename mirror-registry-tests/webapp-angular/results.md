# Webapp Angular — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175678 | none | PASSED |
| With npm proxy | build-and-deploy-20000175682 | pkg-npm-* | PASSED |

## Test 1: No proxy — PASSED

- 960 packages installed in 22s from default registry
- `missing "NPM_REGISTRY" build argument` warning (expected)
- `ng build` succeeded
- Build succeeded

## Test 2: With npm proxy — PASSED

- 960 packages installed in 2m through Nexus proxy (ngrok)
- ngrok logs confirmed all traffic routed through proxy (200 OK)
- `ng build` succeeded
- Build succeeded, image pushed

## Notes

- Same npm proxy pattern as React — `--build-arg NPM_REGISTRY` + `.npmrc` secret mount
- Angular CLI (`ng build`) works correctly with proxied npm packages
