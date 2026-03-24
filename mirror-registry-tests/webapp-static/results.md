# Webapp Static Files — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175685 | none | PASSED |
| With proxy (fake mirror) | build-and-deploy-20000175684 | oci-choreo-* (fake) | PASSED (build failed as expected) |

## Test 1: No proxy — PASSED

- Nginx image pulled from `choreoanonymouspullable.azurecr.io`
- No Node, no npm — static files only
- Single-stage Dockerfile (14 steps)
- Build succeeded, image pushed

## Test 2: With proxy (fake OCI mirror) — PASSED

- `Logging into proxy mirror: fake-mirror.example.com` appeared in logs
- `podman login` attempted, failed with DNS error (expected)
- Build failed with exit code 125 — correct behavior

## Notes

- Static webapp only uses nginx image — no Node, no npm
- Only OCI mirror keys (`oci-choreo-url`) are relevant
- No package proxy needed
