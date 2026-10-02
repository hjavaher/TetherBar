# Verification record

Candidate: TetherBar 0.1.0. Date: 2026-10-02. Environment: macOS 27.0 (26A428), Apple Silicon, Apple clang 21.0.0. Public source is prepared separately from the previously installed personal prototype.

## Automated evidence

| Command | Exit | Result |
|---|---|---|
| `sh build.sh` | 0 | Universal arm64/x86_64 build; plist lint and strict ad hoc signature verification; 40 connection, freshness, history, and color checks passed; version output `TetherBar 0.1.0`. |
| `sh scripts/test.sh` | 0 | 52 probe security checks passed; Clang static analyzer reported zero diagnostics for both application source files. |
| `lipo -archs build/TetherBar.app/Contents/MacOS/TetherBar` | 0 | Both x86_64 and arm64 slices present. This is compile evidence, not Intel runtime evidence. |
| `codesign -d --verbose=2 build/TetherBar.app` | 0 | Ad hoc signature with hardened runtime; no Team Identifier. |
| `python3 scripts/check-public.py` | 0 | 25 allowlisted public files; sensitive-pattern, relative-link, and version checks passed. |
| `sh -n build.sh scripts/test.sh scripts/release.sh` | 0 | Shell syntax checks passed. |
| `sh scripts/release.sh preview` | 0 | Preview and source ZIPs created; both ZIP integrity checks and SHA-256 verifications passed. |
| `gitleaks dir . --redact --no-banner` | 0 | No leaks found in the prepared public tree. This scanner result supplements manual review and the allowlist. |

The first build attempt failed because the new version command used a property on an untyped Objective-C return value. The command was corrected with an explicit string variable, then rebuilt successfully. The first analyzer attempt encountered the same compiler error; the complete corrected test/analyzer run passed. No test was repeatedly rerun to hide a flaky result.

The initial resource-measurement attempt inside the execution sandbox exited 1 before a usable app run; `time` reported a denied `sysctl` operation. That attempt provides no runtime or performance evidence.

## Size and performance claims

The initial universal executable measured 226,416 bytes; its app bundle occupied approximately 236 KiB on the development filesystem. Bundles and ZIP sizes can change with SDK/compiler/signing versions. This measurement supports describing the binary as small; it does not establish battery consumption.

The design uses a single process, a 20-second timer only while a hotspot is detected, and short 4-second discovery windows. Response buffering is capped at 4 KiB per probe. Apple's system services may do additional work outside this process. No sustained whole-system energy benchmark has been performed.

A subsequent 25-second diagnostic run with normal desktop access exited 0. `/usr/bin/time -l` recorded 25.10 seconds elapsed, 0.08 seconds user CPU, 0.06 seconds system CPU, 60,735,488 bytes maximum resident set size, and 15,320,024 bytes peak memory footprint. RSS and footprint are different measurements. This short sample is not a sustained idle or battery benchmark and does not include work in system services.

## Physical coverage

The personal prototype was observed with an iPhone USB hotspot behind a VPN, returning two cellular bars and generic 5G. Its owner confirmed the menu bar presentation. Those observations do not certify every changed public-build path.

The public build's 25-second diagnostic run detected an active **Wi-Fi hotspot**, reported **5G**, updated from **2 to 4 bars**, and completed a responsive HTTPS check (`internet=1`, `health=0`). It exited automatically. The previously installed app was not replaced, and the public app's Launch at Login setting was not enabled.

The following remain unqualified: live Wi-Fi association switching; multiple nearby phones; non-English USB identification; real sleep/wake and unplug/replug transitions; deliberately induced slow/outage/recovery conditions; older macOS releases; Intel runtime behavior; actual logout/login; and a quarantined download on a separate Mac. Tests for matching, color decisions, staleness, and cancellation are narrower than these physical cases.

## Release evidence

The release script validates the manifest, rebuilds, checks bundle integrity, tests both ZIP containers, and verifies SHA-256 checksums before producing artifacts. The source ZIP includes only `PUBLIC_FILES.txt` entries. No Git commit hash is embedded yet; the release tag must identify the exact published source commit.

GitHub CI and the optional Developer ID/notarization path are separate checks. Do not infer either has passed from a local build. The initial preview must remain marked experimental and unnotarized.
