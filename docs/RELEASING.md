# Releasing TetherBar

## Versioning

`VERSION` is the single source for the numeric `major.minor.patch` version. The build writes it into both `CFBundleShortVersionString` and `CFBundleVersion`. Git tags use `v` followed by that version, for example `v0.1.0`; the `v` is not part of the bundle version.

During `0.x`, increment the patch for compatible fixes and the minor for breaking behavior or support changes. Publish `1.0.0` only after defining and validating a stable supported OS/hardware range. Never replace a published tag or release asset with different bytes; increment the version instead.

## Prepare a release

1. Review the diff and third-party provenance. Keep `LICENSE` aligned with the repository license.
2. Update `VERSION`, `CHANGELOG.md`, and relevant compatibility documentation.
3. Run `sh build.sh`, `sh scripts/test.sh`, and `python3 scripts/check-public.py`. Record failures and fixes as well as final results.
4. Perform and record the physical tests warranted by the changes. Compilation for an OS or architecture is not runtime qualification.
5. Review the exact public manifest and staged Git diff for credentials, personal data, signing material, and unrelated files. The source ZIP includes only `PUBLIC_FILES.txt` entries.
6. Commit the reviewed files. Tag that exact commit and record its SHA in the GitHub release notes.

The build uses only Apple's compiler/frameworks. CI's sole action dependency is pinned to a full commit, and Dependabot checks Actions updates monthly. CI has read-only repository access and never signs, notarizes, or publishes a release.

## Package an unnotarized preview

```sh
sh scripts/release.sh preview
```

This builds an ad hoc signed universal app and creates:

- `TetherBar-0.1.0-universal-preview.zip`, containing the app, license, README, and build information.
- `TetherBar-0.1.0-source.zip`, containing the explicit public source manifest.
- `SHA256SUMS.txt`, containing checksums for both ZIP files.

Files appear under `dist/0.1.0-preview/`. Existing output is never overwritten. To rebuild an unpublished candidate after changes, move its output folder aside, then rerun. Release archives exclude extended attributes and resource forks. Builds are scripted, but byte-for-byte reproducibility across different SDKs, compilers, or signatures is not claimed.

The ZIP is intentional: this app does not require a privileged installer, package scripts, or a background update service.

## Developer ID signing and notarization

The initial local preview did not have an available Developer ID Application identity. The notarized packaging path is provided for a maintainer with an Apple Developer account; it was not exercised for 0.1.0.

Install a Developer ID Application certificate in your login Keychain and store a notarytool credential profile using Apple's documented setup. Set `TETHERBAR_SIGN_IDENTITY` to the identity's name or hash and `TETHERBAR_NOTARY_PROFILE` to the existing Keychain profile name in your shell. These variables reference Keychain entries; do not put private keys, passwords, or API keys in source files or shell history.

Then run:

```sh
sh scripts/release.sh notarized
```

This signs with hardened runtime and a secure timestamp, submits a temporary ZIP to Apple, waits for notarization, staples and validates the ticket, and requires a successful Gatekeeper assessment before producing release assets. The command uploads the application to Apple. It fails if the signing/profile variables are missing or any verification step fails.

Review the notarization result and logs. Test a quarantined download on a separate Mac before describing a release as ready for general installation. Do not add permissive entitlements, disable library validation, or disable Gatekeeper to get a release through validation without understanding and reviewing the reason.

## GitHub setup and publication

The canonical repository is [hjavaher/TetherBar](https://github.com/hjavaher/TetherBar). Configure these repository controls before publication:

- Description: “A very lightweight macOS menu bar app for iPhone hotspot signal and connection health.”
- Topics: `macos`, `menu-bar`, `iphone`, `hotspot`, `objective-c`, `lightweight`.
- Enable private vulnerability reporting, dependency alerts, and available secret scanning/push protection.
- Keep Actions workflow permissions read-only and fork pull request execution subject to GitHub's approval controls. Do not grant Actions permission to approve pull requests.
- Require the CI verification job for changes to the default branch once the first run establishes its check name. Use reviewed pull requests for later changes; prevent force pushes and deletion of release history.

Publish `v0.1.0` as a **pre-release**, with its unnotarized status and compatibility limits prominent. Attach both ZIPs and `SHA256SUMS.txt`, and link the changelog and audit report. Verify the uploaded filenames and checksums, the tag's commit, license recognition, README rendering, and security reporting controls.

## References

Checked 2026-10-02:

- [MIT license](https://choosealicense.com/licenses/mit/): permissive redistribution with copyright/license preservation.
- [Semantic Versioning](https://semver.org/): initial development versions and immutable releases.
- [Apple Developer ID](https://developer.apple.com/developer-id/): distribution outside the Mac App Store.
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): signing and notarization requirements.
- [GitHub Actions security](https://docs.github.com/en/actions/reference/security/secure-use): least privilege, immutable action pins, and untrusted workflow risks.
- [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately): private reports depend on repository configuration as well as a policy file.
