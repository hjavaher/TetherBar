#!/usr/bin/env python3
"""Check the explicit source-release boundary, without printing secret matches."""
# SPDX-License-Identifier: MIT
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
names = (root / "PUBLIC_FILES.txt").read_text().splitlines()
if len(names) != len(set(names)) or not names:
    sys.exit("Invalid or duplicated public file manifest")
patterns = {
    "private key": r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "GitHub token": r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "AWS key": r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "Slack token": r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
    "local user path": r"/(?:Users|home)/[A-Za-z0-9_.-]+/",
    "model marker": r"oaicite|contentReference\[|turn\d+(?:search|view)\d+|utm_source=chatgpt",
}
errors = []
for name in names:
    path = pathlib.PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not re.fullmatch(r"[A-Za-z0-9_./-]+", name):
        errors.append("Invalid manifest path")
        continue
    file = root / name
    if any(part.is_symlink() for part in [file, *file.parents] if part != root.parent):
        errors.append(f"{name}: symlinks are not allowed")
        continue
    if not file.is_file():
        errors.append(f"{name}: missing file")
        continue
    text = file.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        errors.append(f"{name}: missing final newline")
    for kind, pattern in patterns.items():
        if kind == "model marker" and file.suffix != ".md":
            continue
        if re.search(pattern, text):
            errors.append(f"{name}: possible {kind}; review before publishing")
    if file.suffix == ".md":
        for target in re.findall(r"\]\(([^)]+)\)", text):
            if "://" not in target and not target.startswith("#"):
                if not (file.parent / target.split("#")[0]).is_file():
                    errors.append(f"{name}: broken relative link")
version = (root / "VERSION").read_text().strip()
if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
    errors.append("Invalid semantic version")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"PASS: {len(names)} public files, sensitive-pattern scan, relative links, version {version}")
print("Pattern checks supplement human review; they cannot prove the absence of secrets.")
