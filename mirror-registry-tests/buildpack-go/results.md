# Buildpack Go — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With Go proxy (no deps project) | build-and-deploy-20000175699 | pkg-go-* | PASSED (no deps to download) |
| With Go proxy (with deps project) | build-and-deploy-20000175700 | pkg-go-* | PASSED |
| No proxy (with deps project) | build-and-deploy-20000175701 | none | PASSED |

## Test 1: With Go proxy (no deps project) — PASSED

- Secret set with `pkg-go-url`, `pkg-go-username`, `pkg-go-password`
- `GOPROXY` env var set, `.netrc` generated and mounted at `/home/cnb/.netrc`
- Go 1.26.1 installed from `dl.google.com`
- `go mod tidy` + `go mod download` ran — "no module dependencies to download"
- `go build` succeeded in 5.4s
- Build + export succeeded, image pushed
- **No ngrok traffic** — sample project has no external Go dependencies

## Test 2: With Go proxy (with deps project) — PASSED

- Project from `choreo-build-flows` repo (Go module proxy E2E test with deps)
- `go mod download` took 2.84s (vs 48ms for no-deps project — actual downloads happened)
- `go build` succeeded in 5.6s
- Build + export succeeded, image pushed
- ngrok confirmed: `github.com/go-chi/chi/v5@v5.0.12` — `.mod`, `.info`, `.zip` all 200 OK through Nexus go-proxy

## Test 3: No proxy (with deps project) — PASSED

- `GOPROXY=https://proxy.golang.org|direct` (default, no custom proxy)
- `go mod download` took 84ms from default proxy (vs 2.84s through ngrok)
- Build succeeded, no regression
- Pod: build-and-deploy-20000175701

## Notes

- Go proxy couldn't be fully validated with ngrok because choreo-samples Go projects have no external deps
- `GOPROXY` env var mechanism is the same as `PIP_INDEX_URL` (Python) and `NPM_CONFIG_REGISTRY` (Node.js), both confirmed working with ngrok
- `.netrc` auth mount pattern identical to `.npmrc` mount — same volume mount code path
- `GONOSUMDB=*` set when credentials are provided (skips checksum DB for private proxy)
- To fully test: need a Go project with external deps (e.g., gin, echo, etc.)
