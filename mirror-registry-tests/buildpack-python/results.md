# Buildpack Python — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With PyPI proxy | build-and-deploy-20000175697 | pkg-python-* | PASSED |
| No proxy | build-and-deploy-20000175698 | none | PASSED |

## Test 1: With PyPI proxy — PASSED

- `Looking in indexes: https://<nexus-username>:****@6709-...ngrok.../repository/pypi-proxy/simple`
- All packages downloaded through Nexus: Flask, gunicorn, blinker, click, itsdangerous, jinja2, markupsafe, werkzeug, packaging
- ngrok confirmed: all 200 OK for `.whl` and `/simple/` requests
- pip install completed in 19.5s
- Python 3.10.20, Google buildpack `google.python.pip@0.9.2`
- Build + export succeeded, image pushed
- Pod: build-and-deploy-20000175697

## Test 2: No proxy — PASSED

- pip install from default `pypi.org` (no `PIP_INDEX_URL` override)
- Build succeeded, no regression
- Pod: build-and-deploy-20000175698

## Notes

- `PIP_INDEX_URL` with embedded credentials (`https://user:pass@host/path`) works correctly
- POSIX parameter expansion used for URL credential embedding (no sed)
- Python runtime downloaded from `us-docker.pkg.dev` (not proxied — Google buildpack internal)
