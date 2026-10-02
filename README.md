# TetherBar

**A very lightweight macOS menu bar app that shows your iPhone's cellular signal while you're connected to its Personal Hotspot.**

TetherBar puts cellular bars and a network label such as **5G** or **LTE** beside your Mac's Wi-Fi indicator. It disappears when the Mac is no longer using the hotspot. Its purpose is small: help you tell whether the phone's connection is struggling without picking up the phone.

Version **0.1.0** is experimental. TetherBar uses undocumented Apple APIs, which can change between macOS releases. It reports generic 5G; it cannot distinguish 5G UW, UC, or 5G+.

## Built to stay light

TetherBar is a native Objective-C/AppKit app with no third-party runtime dependencies. It has no bundled browser, Electron runtime, analytics SDK, updater, background helper, or account system.

- One process handles the menu item and connection checks.
- Network-change notifications drive visibility. There is no repeating polling timer while off the hotspot.
- While connected, one timer refreshes roughly every 20 seconds, with 3 seconds of tolerance so macOS can group wakeups.
- Signal discovery runs in short, 4-second windows.
- Internet checks request tiny HTTPS responses. The app retains at most 4 KiB of response data per check, with a 5-second resource timeout per endpoint.
- Disconnecting, sleeping, or quitting cancels discovery and network checks.

These choices keep the app's work small. They do not mean zero battery use: Apple's Sharing and Wi-Fi services also do work on its behalf. TetherBar does not run bandwidth-heavy speed tests. Build size and the limits of performance testing are recorded in [verification](docs/VERIFICATION.md).

## What the indicator means

The bars describe the **iPhone's cellular signal**, not the Wi-Fi link between the Mac and the phone. Apple supplies a value from 0 to 4.

| Color | Cellular signal | Internet check |
|---|---|---|
| Normal menu bar color, usually white in a dark menu bar | 5G with at least 2 bars; LTE or older service with at least 3 bars | Responsive |
| Light yellow | 5G with 1 bar or less; LTE or older service with 2 bars or less | Responsive, or still checking |
| Light yellow | Missing, stale, or unknown cellular information | No confirmed internet failure |
| Light red | Any signal strength | Failed, very slow, or repeatedly unstable checks |

A successful tiny request taking more than 3 seconds counts as very slow. If the first endpoint fails or is slow, TetherBar checks a second provider. A fast successful fallback counts as responsive. After at least two bad rounds among the last five, two consecutive responsive rounds clear the unstable state.

This is a rough usability indicator. It does not measure download speed, guarantee that every site works, or prove that traffic is using cellular data. A VPN, proxy, captive portal, or blocked check endpoint can affect the result. Updates are periodic, so a change may take a refresh cycle and request timeouts to appear.

## Requirements and compatibility

- A Mac running macOS 13 or later is the build target. **Earlier macOS versions have not been runtime-qualified; the tested development system is macOS 27.0 on Apple Silicon.** A deployment target alone does not prove compatibility with private APIs.
- An iPhone with an active Personal Hotspot connection to the Mac over Wi-Fi or USB.
- macOS must expose the phone's hotspot metadata through its Sharing service. Normal Apple Continuity/Instant Hotspot setup may be needed; TetherBar cannot grant itself access.

The release binary is universal (`arm64` and `x86_64`). Intel runtime behavior is untested. USB tethering behind a VPN was observed during development. Live Wi-Fi association switching, non-English USB descriptions, and sleep/wake transitions still need broader hardware testing.

## Install

Download the preview ZIP from [Releases](https://github.com/hjavaher/TetherBar/releases), extract it, and move `TetherBar.app` to Applications before opening it. Keep one installed copy.

**The initial preview is ad hoc signed and is not Apple-notarized.** macOS may block a downloaded preview. Building from source is the recommended option for this experimental release. If you choose a downloaded preview, review the source and checksum first, then use the per-app option in **System Settings → Privacy & Security** if macOS offers it. Do not disable Gatekeeper or other system protections globally. An ad hoc signature checks local bundle integrity but does not establish a publisher's identity.

From the directory containing the downloaded assets, verify their integrity with:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Checksums detect mismatched downloads; they do not authenticate a release if both the ZIP and checksum are replaced. A future notarized build will be labeled explicitly in its release notes.

## Use

1. Open TetherBar and connect the Mac to the iPhone's hotspot.
2. Click the indicator for connection details, **Launch at Login**, **Place Beside Wi-Fi**, and **Quit TetherBar**.
3. Enable **Launch at Login** if you want it to start automatically. Approve it in macOS Login Items if prompted.

macOS controls menu bar placement. TetherBar makes a best-effort placement using its own saved position near the Wi-Fi item. You can also hold **Command** and drag the item. A notch or a menu bar manager can hide it when space is limited.

When disconnected, the menu item disappears but the app continues listening for connection changes. Reopen it from Applications or Spotlight to access login settings or Quit while the indicator is hidden. If it crashes, open it again the same way, or run:

```sh
open -a TetherBar
```

Launch at Login is optional and uses Apple's `SMAppService`. TetherBar does not install a watchdog or automatically relaunch after a crash.

## Build from source

Install Apple's Xcode Command Line Tools, then clone and build:

```sh
xcode-select --install
git clone https://github.com/hjavaher/TetherBar.git
cd TetherBar
sh build.sh
open build/TetherBar.app
```

The build uses Apple's compiler and frameworks, creates a universal app, applies an ad hoc hardened-runtime signature, and runs the built-in decision tests. It does not download dependencies. Move the app to Applications before enabling Launch at Login.

For the network security tests and static analysis:

```sh
sh scripts/test.sh
```

Python 3 is needed for the public-file checks and release packaging, but is never needed to run the app:

```sh
python3 scripts/check-public.py
sh scripts/release.sh preview
```

Release files appear in `dist/0.1.0-preview/`. Packaging refuses to overwrite an existing version directory. [Release instructions](docs/RELEASING.md) explain versioning, signing, notarization, and publication.

## Diagnostics

The executable has a few maintenance commands:

| Option | Behavior |
|---|---|
| `--version` | Print the app version and exit |
| `--self-test` | Test connection selection, freshness, internet history, and colors without contacting a phone |
| `--diagnose` | Run for 25 seconds, print status changes, and exit; while on a hotspot this performs the normal HTTPS checks |
| `--login-status` | Print macOS login-item registration status |
| `--enable-login` / `--disable-login` | Change login-item registration for this app copy |

For example, with the app installed in Applications:

```sh
/Applications/TetherBar.app/Contents/MacOS/TetherBar --version
/Applications/TetherBar.app/Contents/MacOS/TetherBar --self-test
```

Quit any running TetherBar before running `--diagnose`, so two copies do not show two indicators. Diagnostic state output omits phone names, SSIDs, IP addresses, and device identifiers. Check screenshots and other logs for personal information before attaching them to an issue.

## Privacy and security

TetherBar keeps connection and signal readings in memory. It uses the current network name locally to match the phone; it does not write a signal history or send phone names to a server. macOS stores menu position and login-item preferences.

While connected, the app contacts:

| Provider | Endpoint | When |
|---|---|---|
| Apple | `https://captive.apple.com/hotspot-detect.html` | Each internet-check round |
| Google | `https://www.gstatic.com/generate_204` | When Apple's response fails or takes more than 3 seconds |

These providers can observe your public IP address, request timing, and ordinary HTTP/TLS metadata. Requests use your Mac's normal routing, proxy, and VPN settings. There is no analytics service or application backend. Quitting the app stops these requests.

The probe keeps normal TLS certificate validation, refuses redirects, disables cookie/cache/credential storage, rejects non-server-trust authentication challenges, and limits buffered response data. It does not ask for administrator access, Full Disk Access, Accessibility, or Screen Recording. It has no custom URL scheme, local web server, or updater.

The app is **not App Sandboxed**. Hardened runtime is a separate protection and does not confine all filesystem access. Private framework compatibility and device attribution remain limitations. Read the [security policy](SECURITY.md) and [security audit](docs/SECURITY_AUDIT.md) for the reviewed boundaries and remaining risks.

## Known limitations

- Private Apple frameworks may change or disappear. Selector checks help with missing methods; they cannot guarantee compatibility with changed method signatures or behavior.
- **5G UW/UC/5G+ is not available through the observed metadata.** TetherBar displays `5G` without inferring a carrier badge.
- Wi-Fi matching needs both Personal Hotspot classification and an exact match between the associated network name and one discovered phone name. Ambiguous matches produce unknown signal.
- USB detection currently uses macOS's English hardware description `iPhone USB`. USB signal selection accepts exactly one discovered candidate, but cannot cryptographically bind that candidate to the cable-connected phone. It may select the wrong phone if only an unrelated candidate is discovered.
- Under a VPN, TetherBar uses the first active physical service in macOS service order as an underlay estimate. Multiple interfaces or split routing can make that estimate wrong.
- Signal readings expire after 60 seconds. Cached discovery records do not extend their lifetime.
- The internet color reflects the check endpoints and route. It is unsuitable as a security or availability guarantee.
- There is no Bluetooth-tethering support or automatic update system.

## Contributing and license

Keep contributions consistent with the app's small scope and low resource use. See [CONTRIBUTING.md](CONTRIBUTING.md) for build, test, privacy, and review expectations.

TetherBar is available under the [MIT license](LICENSE). You can use, modify, and redistribute it, including commercially, while preserving the copyright and license notice. Apple's frameworks remain Apple's software and are loaded from macOS; they are not bundled with TetherBar. This project is not affiliated with Apple or any mobile carrier.
