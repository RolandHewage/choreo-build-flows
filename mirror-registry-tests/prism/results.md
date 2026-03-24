# Prism Mock — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175687 | none | PASSED |
| With proxy (fake OCI mirror) | build-and-deploy-20000175686 | oci-choreo-* (fake) | PASSED (build failed as expected) |
| With npm proxy | build-and-deploy-20000175688 | pkg-npm-* | PASSED (build succeeded) |

## Test 1: No proxy — PASSED

- `npm install` ran (2 packages for prism-docker-resource-generator)
- Prism image from `choreocontrolplane.azurecr.io/stoplight/prism:5`
- Golang image from `choreocontrolplane.azurecr.io/golang:1.22.4-alpine`
- Go traffic router built successfully
- Build succeeded, image pushed (482 MB)

## Test 2: With proxy (fake OCI mirror) — PASSED

- `Logging into proxy mirror: fake-mirror.example.com` appeared in logs
- `podman login` attempted, failed with DNS error (expected)
- Build failed with exit code 125 — correct behavior

## Test 3: With npm proxy — PASSED

- Build succeeded with `pkg-npm-url` and `pkg-npm-token` set
- `npm install` completed (2 packages in 317ms)
- Only 2 packages — may have been served from cache; check ngrok logs to confirm proxy was used
- No build regression with npm proxy keys present

## Notes

- Prism uses both OCI images (prism, golang) AND npm (for resource generator script)
- `_proxy_login prism` handles OCI mirror auth
- `_setup_npm_proxy prism` handles npm proxy
- `_resolve_image prism image-prism-ref oci-choreo-url` resolves prism image
- `_resolve_image prism image-golang-ref oci-choreo-url` resolves golang image
