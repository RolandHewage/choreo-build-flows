# Buildpack Java/Gradle — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With Gradle proxy | build-and-deploy-20000175695 | pkg-gradle-* | PASSED |
| No proxy | build-and-deploy-20000175696 | none | PASSED |

## Test 1: With Gradle proxy — PASSED

- Gradle init script picked up: `--init-script=/tmp/gradle-proxy-binding/init.gradle`
- Google buildpack `google.java.gradle@0.10.0` detected
- Gradle v9.4.1 installed
- Build completed in 10s (`gradle clean assemble -x test`)
- Encoding warnings in App.java (non-blocking — special characters in string literal)
- Image exported and pushed
- JDK 17.0.18_8 from Google buildpack runtime

## Test 2: No proxy — PASSED

- No `--init-script` flag in Gradle command (no proxy secret = no init.gradle)
- Gradle took 5.9s (vs 10s with proxy)
- Build succeeded, no regression

## Notes

- `_setup_gradle_proxy` generates `init.gradle` with `allprojects { repositories { maven { url } } }`
- Auth via `credentials { username; password }` block
- Gradle uses `GRADLE_OPTS=-I /tmp/gradle-proxy-binding/init.gradle` (passed via `_LANG_ENV --env`)
- Gradle downloads from `services.gradle.org` for the wrapper (not proxied — Google buildpack internal)
- Dependencies resolved through the proxy init script
