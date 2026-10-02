# Changelog

Versions follow [Semantic Versioning](https://semver.org/). The `0.x` series is experimental; changes to private API behavior or supported environments may require a minor version change.

## 0.1.0 - 2026-10-02

Initial public preview, named TetherBar.

- Displayed iPhone cellular bars and generic 5G/LTE labels only while a detected Wi-Fi or USB hotspot connection was in use.
- Added normal, light yellow, and light red states for signal and basic internet usability.
- Included optional Launch at Login, Quit, and best-effort placement beside Wi-Fi.
- Used short discovery windows and event-driven connection changes to limit background work.
- Bounded connectivity response buffering, refused redirects and credential challenges, and preserved system TLS validation.
- Used monotonic signal freshness and checked additional private API selectors and payload types.
- Added MIT licensing, universal preview packaging, security documentation, automated checks, and contributor guidance.

The preview does not distinguish 5G UW/UC, is not notarized, and has limited hardware/OS validation. See [verification](docs/VERIFICATION.md).
