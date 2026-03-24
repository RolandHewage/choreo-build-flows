# Buildpack Java/Maven — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| No proxy | build-and-deploy-20000175694 | none | PASSED |
| With Maven proxy | build-and-deploy-20000175693 | pkg-maven-* | PASSED |

## Test 1: No proxy — PASSED

- Maven took 12s (direct from `repo1.maven.org`)
- No `--settings` flag in Maven command (no proxy secret = no settings.xml binding)
- Spring Boot 3.0.5 product-catalog-app built successfully
- No regression

## Test 2: With Maven proxy — PASSED

- Maven binding picked up: `--settings=/platform/bindings/maven-settings/settings.xml`
- Maven build took 11m48s (through ngrok proxy — slower due to tunneling)
- All Maven artifacts downloaded through Nexus proxy
- ngrok confirmed: all 200 OK for guava, commons-lang3, j2objc, error_prone, asm, failureaccess, etc.
- JDK 17.0.18_8 from Google buildpack runtime
- Build succeeded, image pushed

## Notes

- Google buildpack `google.java.maven@0.9.1` automatically uses settings.xml from CNB binding path
- The `_setup_maven_proxy` function generates settings.xml with `<mirror>` and `<server>` (for auth)
- Maven wrapper (`./mvnw`) is used — not system Maven
- JDK downloaded from `us-docker.pkg.dev` (not proxied — Google buildpack internal)
- Build time difference (12s vs 11m48s) is due to ngrok latency, not a code issue
