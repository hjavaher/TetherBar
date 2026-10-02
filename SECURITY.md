# Security policy

TetherBar is experimental software. Security fixes target the latest tagged release; there is no commitment to backport fixes to older preview versions.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/hjavaher/TetherBar/security/advisories/new), also available under **Security → Report a vulnerability**. Include the version, macOS version, reproduction steps, impact, and a small redacted example when possible.

If that control is unavailable, open an issue requesting a private contact channel without including vulnerability details. Do not put credentials, phone names, network identifiers, or exploit details into public issues. This is a small volunteer project; there is no guaranteed response time.

## Security boundaries

TetherBar provides an informational display. Signal readings and internet colors must not be used as proof of phone identity, route authenticity, or network security. In particular, USB candidate matching and VPN underlay selection are heuristics.

The app has no backend, analytics SDK, embedded browser, automatic updater, privileged helper, or inbound listener. It runs with the logged-in user's permissions and is not App Sandboxed. It reads hotspot information through undocumented system frameworks and sends bounded HTTPS connectivity checks while a hotspot connection is detected.

The [README](README.md) lists external endpoints and privacy behavior. The [audit report](docs/SECURITY_AUDIT.md) describes confirmed fixes, tests, and unresolved limitations. A review reduces known risk; it is not a security certification.

## Distribution

The initial preview is ad hoc signed and unnotarized. Verify the release notes, source, and checksums before running it. A checksum obtained from the same compromised source as a binary would not establish authenticity. Do not disable macOS security protections globally to install TetherBar.

Maintainers should use Developer ID signing, hardened runtime, secure timestamps, and Apple notarization for future broadly distributed binaries. Keep signing keys and credentials in Keychain or an approved secret store, never in this repository or a release asset.
