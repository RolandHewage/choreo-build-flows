# Buildpack Ruby — Mirror Registry Test Results

**Date:** 2026-03-24
**Namespace:** `dp-builds-4f7c3eef-178e-4d4f-8a99-bb360854ffa8`

## Summary

| Test | Pod | Secret | Result |
|---|---|---|---|
| With RubyGems proxy | build-and-deploy-20000175726 | pkg-rubygems-* | PASSED |
| No proxy | build-and-deploy-20000175727 | none | PASSED |

## Test 1: With RubyGems proxy — PASSED

- Gemfile source rewritten from `https://rubygems.org` to ngrok URL via `sed`
- `Fetching gem metadata from https://6709-...ngrok.../repository/rubygems-proxy/` confirmed in logs
- `bundle lock`, `bundle install` all fetched through proxy
- Gems installed: sinatra 2.2.3, rack 2.2.8, webrick 1.7.0, tilt 2.0.11, mustermann 2.0.2, rack-protection 2.2.3, ruby2_keywords 0.0.5
- `BUNDLE_<HOST>` env var set for auth (dots→`__`, dashes→`___`, uppercase)
- Ruby 3.1.7, RubyGems 3.3.15, Bundler 2.3.15
- Build + export succeeded, image pushed
- Pod: build-and-deploy-20000175726

## Test 2: No proxy — PASSED

- `Fetching gem metadata from https://rubygems.org/` — default source, no rewrite
- `bundle install` took 979ms (vs 7.7s through ngrok proxy)
- Build succeeded, no regression
- Pod: build-and-deploy-20000175727

## Notes

- Google buildpack deletes `.bundle/` before `bundle install` — so `.bundle/config` mirror approach doesn't work
- Solution: Gemfile source URL modification via `sed` + auth via `BUNDLE_<HOST>` env var
- Confirmed working on real cluster (matches E2E test findings)
