# Test Runner (Postman/Newman) — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With npm proxy | build-and-deploy-20000175730 | pkg-npm-* | PASSED |
| No proxy | build-and-deploy-20000175731 | none | PASSED |

## Test 1: With npm proxy — PASSED

- Node image from `docker.io/library/node:18-alpine`
- `npm i -g newman` installed 148 packages in 56s through Nexus proxy
- ngrok confirmed all 200 OK: commander, async, colors, tough-cookie, cli-table3, filesize, chardet, mkdirp, cli-progress, lodash
- `.npmrc` secret mount with `_authToken` working
- Docker build succeeded, image created
- Trivy scan failed (exit code 1) — vulnerability scan issue, NOT proxy-related
- Pod: build-and-deploy-20000175730

## Test 2: No proxy — PASSED

- `missing "NPM_REGISTRY" build argument` warning (expected — no proxy)
- `npm i -g newman` took 4s from default registry (vs 56s through ngrok)
- 148 packages installed, no regression
- Trivy scan failed (exit code 1) — pre-existing vulnerability scan issue
- Pod: build-and-deploy-20000175731

## Notes

- Test runner uses same npm proxy pattern as webapp: `--build-arg NPM_REGISTRY` + `.npmrc` secret mount
- `_proxy_login test-runner` handles OCI mirror auth
- `_resolve_image test-runner image-node-ref oci-dockerhub-url` resolves node image
- Newman/Postman packages fetched through proxy
