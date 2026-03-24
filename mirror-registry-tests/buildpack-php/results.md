# Buildpack PHP/Composer — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With Composer proxy (no deps project) | build-and-deploy-20000175732 | pkg-composer-* | PASSED (no composer.json — proxy not exercised) |
| With Composer proxy (monolog project) | build-and-deploy-20000175733 | pkg-composer-* | PASSED (ngrok confirmed!) |
| No proxy (monolog project) | build-and-deploy-20000175734 | none | PASSED |

## Test 1: With Composer proxy (no deps) — PASSED (limited)

- Sample project has no `composer.json` — proxy code skipped
- Build succeeded, no regression
- Pod: build-and-deploy-20000175732

## Test 2: With Composer proxy (monolog project) — PASSED

- Project: `choreo-build-flows/buildpack/php-composer-test/` with `monolog/monolog ^3.0`
- `google.php.composer@0.9.1` and `google.php.composer-install@0.0.1` detected
- Composer v2.2.24 installed
- `composer install` fetched monolog/monolog 3.10.0 and psr/log 3.0.2 through Nexus proxy
- ngrok confirmed all 200 OK:
  - `packages.json`
  - `p2/monolog/monolog.json`
  - `p2/psr/log.json`
  - `psr-log-3.0.2.zip`
  - `monolog-monolog-3.10.0.zip`
- `composer.json` modified by `jq` to add proxy repository
- `auth.json` generated with `http-basic` credentials
- Build + export succeeded, image pushed
- Pod: build-and-deploy-20000175733

## Test 3: No proxy (monolog project) — PASSED

- `composer install` took 922ms from default packagist.org (vs 7s through proxy)
- monolog/monolog 3.10.0 and psr/log 3.0.2 fetched directly
- No regression without proxy
- Pod: build-and-deploy-20000175734

## Notes

- Composer proxy modifies `composer.json` inline via `jq` to prepend proxy repository and disable packagist.org
- Auth via `auth.json` with `http-basic` credentials in project directory
- Google buildpack `google.php.composer@0.9.1` runs `composer install`
- PHP 8.1.34, Nginx 1.29.6, Composer v2.2.24
