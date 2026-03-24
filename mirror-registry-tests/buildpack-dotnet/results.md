# Buildpack .NET/NuGet — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With NuGet proxy (greeter, no ext deps) | build-and-deploy-20000175704 | pkg-nuget-* | PASSED |
| With NuGet proxy (dotnet-nuget-test, Newtonsoft.Json) | build-and-deploy-20000175664 | pkg-nuget-* | PASSED |
| With NuGet proxy (dotnet-nuget-test, retest) | build-and-deploy-20000175708 | pkg-nuget-* | PASSED |
| No proxy (dotnet-nuget-test) | build-and-deploy-20000175712 | none | PASSED |
| Pre-fix (/workspace mount) | build-and-deploy-20000175657 | pkg-nuget-* | FAILED (exporter permission denied) |

## Test 1: With NuGet proxy (greeter) — PASSED

- NuGet.Config mounted at `/home/cnb/.nuget/NuGet/NuGet.Config` (user-level, post-fix)
- `dotnet restore` completed in 63ms (no external packages)
- Exporter succeeded — mount path fix confirmed
- Pod: build-and-deploy-20000175704

## Test 2: With NuGet proxy (dotnet-nuget-test) — PASSED

- `Restored /workspace/dotnet-nuget-test.csproj (in 29.74 sec)` — Newtonsoft.Json 13.0.3 downloaded through Nexus
- ngrok confirmed NuGet proxy traffic
- Exporter succeeded
- Pod: build-and-deploy-20000175664

## Test 3: With NuGet proxy (dotnet-nuget-test, retest) — PASSED

- Retest of Test 2 to confirm consistency
- `Restored /workspace/dotnet-nuget-test.csproj` through Nexus proxy
- Exporter succeeded — mount path fix stable
- Pod: build-and-deploy-20000175708

## Test 4: No proxy (dotnet-nuget-test) — PASSED

- `Restored /workspace/dotnet-nuget-test.csproj (in 845 ms)` — from default `nuget.org`
- Confirms proxy was used in test 3 (30s vs 845ms — 35x slower through ngrok)
- No regression without proxy
- Pod: build-and-deploy-20000175712

## Test 5: Pre-fix (exporter failure) — FAILED (expected)

- NuGet.Config mounted at `/workspace/NuGet.Config` (old path)
- Exporter failed: `failed to add file /workspace/NuGet.Config to archive: open /workspace/NuGet.Config: permission denied`
- This led to the mount path fix (PR: fix/nuget-proxy-mount-path-exporter-permission)
- Pod: build-and-deploy-20000175657

## Bug Fixed

- **NuGet.Config mount path**: Changed from `/workspace/NuGet.Config` to `/home/cnb/.nuget/NuGet/NuGet.Config`
- Root cause: Buildpack lifecycle exporter archives everything in `/workspace/`, volume-mounted file had restrictive permissions
- Fix: Mount to user-level NuGet config path (`$HOME/.nuget/NuGet/NuGet.Config` where `HOME=/home/cnb`), outside `/workspace/`

## Notes

- NuGet.Config uses `<clear />` to override all default sources
- `<packageSourceCredentials>` for auth with `ClearTextPassword`
- SDK workload manifest checks show 401/404 in ngrok — non-blocking (these are optional SDK checks, not app package downloads)
- Same mount fix also prevents cross-contamination: NuGet.Config no longer breaks non-.NET buildpack builds when `pkg-nuget-url` is in the secret
