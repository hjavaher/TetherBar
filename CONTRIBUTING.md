# Contributing to TetherBar

TetherBar should remain a very lightweight utility focused on showing iPhone hotspot signal and basic connection usability. Prefer Apple frameworks and small changes. Discuss new dependencies, background services, telemetry, or continuous polling before adding them.

## Development

Use a Mac with Xcode Command Line Tools. Python 3 is required for release checks. Start a branch from the repository's default branch and keep each pull request focused on one behavior or problem.

```sh
sh build.sh
sh scripts/test.sh
python3 scripts/check-public.py
```

The first command builds both CPU architectures and runs decision tests. The second uses local URL-protocol fixtures for probe security tests and runs Clang's static analyzer. Neither command intentionally interrupts your network. CI performs these checks and packages a preview without signing credentials or publication permissions.

Add focused regression coverage for changed boundaries or decisions. Do not call a logic test evidence of physical Wi-Fi, USB, VPN, or sleep/wake behavior. Report your actual macOS version and architecture when testing those paths.

## Review expectations

- Keep work bounded: short discovery windows, finite request timeouts, bounded response data, and cancellation when disconnected or sleeping.
- Keep external data out of commands, logs, and persistent storage. Validate types, ranges, freshness, ambiguity, and callback generation before using it.
- Preserve normal TLS validation. Redirects and HTTP authentication are intentionally refused by connectivity checks.
- New external destinations, permission requests, or retained data require an explicit explanation and updates to the privacy documentation.
- Keep private framework loading restricted to fixed system paths. Document compatibility limits rather than silently claiming support.
- Keep Actions pinned to reviewed commit hashes, with minimum permissions. Pull request jobs must not receive publishing or signing secrets.
- Update `PUBLIC_FILES.txt` when adding a file intended for source releases. Build outputs, credentials, personal diagnostics, and private investigation notes do not belong in Git.

Run the public-file scan before submitting, and review the actual diff for secrets and personal data. The scanner detects only selected patterns. Use [private vulnerability reporting](https://github.com/hjavaher/TetherBar/security/advisories/new) for security findings rather than a public issue.

## Licensing

Contributions are submitted under the repository's MIT license. Preserve applicable copyright notices and document any third-party code or asset provenance. Do not copy or redistribute Apple's private framework binaries or SDK content into the repository.
