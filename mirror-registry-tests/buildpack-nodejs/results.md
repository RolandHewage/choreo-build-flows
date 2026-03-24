# Buildpack Node.js — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With npm proxy | build-and-deploy-20000175702 | pkg-npm-* | PASSED |
| No proxy | build-and-deploy-20000175703 | none | PASSED |

## Test 1: With npm proxy — PASSED

- Google buildpack `google.nodejs.npm@1.1.1` detected
- Node.js 20.20.1 installed
- `npm ci --quiet --no-fund --no-audit` ran with `NPM_CONFIG_REGISTRY` set
- 60 packages installed in 8s through Nexus proxy
- ngrok confirmed: all 200 OK for express deps (array-flatten, accepts, ms, content-disposition, debug, body-parser, bytes, clone, cookie, etc.)
- `.npmrc` mounted at `/home/cnb/.npmrc` with `_authToken`
- Build + export succeeded, image pushed

## Test 2: No proxy — PASSED

- `npm ci` took 814ms from default registry (vs 8s through ngrok)
- 60 packages installed, no regression
- No `NPM_CONFIG_REGISTRY` override
- Pod: build-and-deploy-20000175703

## Notes

- `NPM_CONFIG_REGISTRY` env var via `pack build --env` — same mechanism as webapp but inside buildpack container
- `.npmrc` volume mount at `/home/cnb/.npmrc` for auth token
- Google buildpack uses `npm ci` (not `npm install`) — requires `package-lock.json`
