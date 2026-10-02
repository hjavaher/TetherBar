# Security audit: TetherBar 0.1.0

Reviewed 2026-10-02. This report covers the initial public source and preview packaging. It is a source review and focused verification by the project's implementation agent, not an independent penetration test or certification.

## Scope and standard

The review covered every app source file, its plist, CLI paths, build and packaging scripts, tests, public-file manifest, and GitHub Actions configuration. It also reviewed the inherited prototype to find behaviors that needed changing before public distribution.

The baseline follows the owner's existing native-app project standards: minimum permissions, no default analytics, normal TLS validation, bounded external data, explicit ownership and cancellation, redacted diagnostics, evidence-based compatibility claims, and credentials kept outside source and release files. Server authentication, database access control, payment flows, browser script injection, and cloud infrastructure checks are inapplicable because this app has none of those surfaces.

## Threat model

Assets include the user's network/device metadata, credentials that the operating system might otherwise offer during authentication, local account privileges, battery and memory, and the integrity of distributed builds.

Inputs cross four boundaries:

1. macOS network configuration and undocumented Sharing/CoreWiFi objects enter connection and signal selection.
2. HTTPS responses from two fixed providers enter the usability check. A captive portal, enterprise TLS interception setup, misconfigured provider, or compromised endpoint might return unexpected responses.
3. Source, build tools, and CI actions produce binaries with the user's trust. A malicious contributor or compromised build dependency could alter those binaries.
4. GitHub hosts source, tags, and release assets. Repository access and release identity are part of distribution security.

The app does not authenticate a hotspot or protect user traffic. A cellular label or successful connectivity check is not evidence of a trusted phone or network. A hostile local administrator, compromised macOS installation, or maliciously modified source tree is outside the protection this app can provide.

## Findings and fixes

Severities describe this utility's exposure rather than an asserted CVSS score. No confirmed high or critical issue was identified in the reviewed application source. Distribution and compatibility limitations remain below.

| ID | Severity | Finding | Resolution and evidence |
|---|---|---|---|
| TB-001 | Medium | The prototype buffered an entire response before checking its size. A very large or compressed response could use excessive memory. | Fixed in `HBProbe.m`: reject excessive declared lengths, check each delivered chunk before appending, cancel at the 4 KiB limit. Tests cover huge advertised lengths and a chunked over-limit body. NSURLSession's internal buffers are OS-owned and are not covered by the 4 KiB claim. |
| TB-002 | Medium | URLSession followed redirects before checking the final hostname. A provider or trusted interception proxy could cause requests to an unintended destination. | Fixed: all redirect delegate callbacks return no request; exact final URL, expected status, and expected content are checked. A rejected redirect cannot reset to success. Focused delegate-contract and wrong-destination tests pass. |
| TB-003 | Low | Authentication and credential handling depended on session defaults. Ephemeral storage is private/in-memory by default, so this was not evidence of a leaked shared password. | Hardened: credential storage explicitly disabled; cookies and caches disabled; Basic, NTLM, Negotiate, and client-certificate challenges canceled. Server trust uses normal system handling. Tests cover both session and task challenge callbacks. |
| TB-004 | Low | Freshness used wall-clock time, so a clock change could extend stale readings. | Fixed: monotonic uptime and rejection of negative age, expired readings, fractional bars, nonnumeric bars, and invalid ranges. Decision tests cover these cases. |
| TB-005 | Low | Some private methods were invoked without availability checks, and device names/arrays were assumed to have expected types. | Hardened: guard every invoked interface selector, validate discovered collection/name types, bound candidate count to 64 and name length to 256. Malformed collections clear the reading. ABI changes and failures inside Apple's private implementation remain unsupported. |
| TB-006 | Low | Personal prototype files were unsuitable for direct public upload because they included local paths and investigation artifacts. | Fixed at the publication boundary: a separate clean source directory and explicit release manifest. Historical private notes and installed app copies remain outside the public tree. Pattern scanning and archive inspection supplement manual review. |

## Reviewed controls

| Surface | Review result |
|---|---|
| TLS and endpoint scope | HTTPS-only fixed Apple/Google URLs. No ATS exceptions, trust-all callbacks, user-controlled endpoint, certificate bypass, or credential injection. System trust, proxies, and VPN routing still apply. |
| Resource exhaustion | One active probe at a time, finite 4-second request/5-second resource deadlines per endpoint, at most one fallback, bounded retained body, bounded discovered candidate count. No throughput downloads. |
| Concurrency and lifecycle | Probe delegate delivery and app state run on the main thread. Weak app capture, generation checks, cleared completion on cancellation, and session invalidation limit stale callbacks. Disconnect, sleep, and quit stop active work. |
| Discovery and identity | A detected active physical hotspot connection is required before showing the item. Wi-Fi requires a unique exact-name match. Cached data does not extend freshness. USB and VPN selection remain heuristics; see limitations. |
| Persistence and diagnostics | Signal/network names stay in memory; own menu position/login preferences persist through macOS facilities. State diagnostics omit names, SSIDs, IP addresses, and identifiers. No telemetry backend or signal history. OS logging is outside this app's control. |
| Privilege and attack surface | Normal user process; no root requests, privileged helper, inbound listener, embedded browser, custom URL scheme, updater, or shell execution in the app. No Apple privacy-permission strings or special entitlements. |
| Dynamic loading | Only fixed absolute paths inside `/System/Library/PrivateFrameworks`. No plugins or user-supplied dylib paths. Libraries remain part of macOS and are not redistributed. |
| Code signing | Preview has ad hoc signing and hardened runtime, with no permissive entitlements. `codesign --verify --strict` checks integrity. Ad hoc signing is not publisher authentication. |
| Build and packaging | Fixed standard tool PATH, quoted variables, strict version format, temporary staging, output symlink checks, no dependency downloads, explicit source allowlist, archive validation and SHA-256 sums. Existing release destinations are not overwritten. |
| Supply chain and CI | No third-party app libraries. Sole CI action pinned to a verified official commit. Read-only token, no persisted checkout credentials, no secrets, no privileged PR trigger, no publishing step. Dependabot configured for Actions updates. Hosted CI has not been treated as passed until a real run succeeds. |
| Documentation and provenance | MIT notice preserved, Apple framework ownership distinguished, external endpoints disclosed, experimental status and measured-versus-untested behavior stated. No bundled proprietary assets. |

## Remaining limitations

1. **Unsigned publisher identity:** the preview is ad hoc signed and unnotarized. A valid Developer ID identity, successful notarization, and a quarantined-download test are prerequisites for claiming a normal trusted macOS distribution. The optional notarized script path has not been exercised.
2. **No App Sandbox:** compromise of the process would have the access of an ordinary user process. Hardened runtime reduces some code-injection risks but is not a filesystem/network sandbox. Private API access has not been qualified under App Sandbox.
3. **Private API dependence:** runtime selector checks cannot protect against all ABI changes, hangs, or crashes in undocumented framework implementations. Support for older macOS versions and Intel hardware remains unqualified.
4. **Attribution heuristics:** USB can select the wrong phone if exactly one unrelated candidate is visible; Wi-Fi names can be duplicated/spoofed; VPN physical underlay choice may be wrong. The display must never be used as authentication.
5. **External observers:** Apple and fallback Google endpoints can observe network metadata. There is no per-provider opt-out in 0.1.0; quitting stops checks. macOS may briefly continue cancellation/cleanup after a network transition.
6. **Usability inference:** endpoint reachability is not a bandwidth measurement or a general internet guarantee. System-trusted interception and endpoint content matching are not content attestation.
7. **Test coverage limits:** fixture tests verify application decisions and delegate contracts, not an adversarial live TLS server, kernel networking, all OS transitions, or sustained battery use. No independent fuzzing campaign or external security assessment was performed.
8. **Repository controls:** private reporting, branch rules, secret scanning availability, and hosted CI must be checked in GitHub itself. Files alone do not enable those settings. Review remote changes separately from this source audit.

## Verification and follow-through

See [verification](VERIFICATION.md) for commands, results, environment, and observed limitations. Use [SECURITY.md](../SECURITY.md) to report new issues privately. Revisit this audit when changing external destinations, credentials, data retention, private APIs, permissions, dependency policy, or the release process.
