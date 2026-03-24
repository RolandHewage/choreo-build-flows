# BYOC — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175671 | none | PASSED |
| With proxy (fake mirror) | build-and-deploy-20000175674 | oci-dockerhub-* (fake) | PASSED (build failed as expected) |

## Test 1: No proxy — PASSED

- Build succeeded, no proxy output in logs
- `FROM golang:1.21-alpine` and `FROM alpine:latest` pulled from `docker.io`
- Trivy scan passed, image pushed to ACR
- No regression

## Test 2: With proxy (fake mirror) — PASSED

- `Logging into proxy mirror: fake-mirror.example.com` appeared in logs
- `podman login` attempted, failed with DNS error (expected for fake URL)
- Build exited with code 125 due to `set -e` — correct behavior
- Confirms `_proxy_login byoc` reads secret and calls `podman login` with correct host/user/pass

## Notes

- BYOC only uses `_proxy_login` — no `_resolve_image` or package proxy
- Customer must change their Dockerfile `FROM` instructions to use the mirror
- `podman login` failure being fatal is correct — customer configured a proxy, silent fallback would bypass security controls
