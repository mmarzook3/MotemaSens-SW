#!/usr/bin/env python3
"""Update the MotemaSens-SW manifest with mobile app release metadata."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path


RAW_BASE = "https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_posix(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="manifest.json")
    parser.add_argument("--version", required=True)
    parser.add_argument("--public-version", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--source-commit", default="")
    parser.add_argument("--release-date", default=dt.date.today().isoformat())
    parser.add_argument("--android-package", default="uk.nwatt.motemasens")
    parser.add_argument("--play-store-url", default="")
    parser.add_argument("--play-in-app-update-supported", action="store_true")
    parser.add_argument("--ios-app-store-url", default="")
    args = parser.parse_args()

    repo_root = Path.cwd()
    manifest_path = repo_root / args.manifest
    apk_path = (repo_root / args.apk).resolve()
    apk_rel = relative_posix(apk_path, repo_root)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    releases = []
    app = manifest.get("app")
    if isinstance(app, dict) and isinstance(app.get("releases"), list):
        releases = [
            release
            for release in app["releases"]
            if release.get("version") != args.version
            and release.get("publicVersion") != args.public_version
        ]

    release = {
        "version": args.version,
        "publicVersion": args.public_version,
        "name": args.name,
        "releaseDate": args.release_date,
        "notes": args.notes,
        "sourceCommit": args.source_commit,
        "platforms": {
            "android": {
                "package": args.android_package,
                "playStoreUrl": args.play_store_url,
                "playInAppUpdateSupported": args.play_in_app_update_supported,
                "apk": {
                    "path": apk_rel,
                    "url": f"{RAW_BASE}/{apk_rel}",
                    "sha256": sha256_file(apk_path),
                    "size": apk_path.stat().st_size,
                },
            },
            "ios": {
                "appStoreUrl": args.ios_app_store_url,
            },
        },
    }

    manifest["app"] = {
        "schema": 1,
        "latest": args.version,
        "releases": [release, *releases],
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {manifest_path} with app {args.version}")
    print(f"APK sha256: {release['platforms']['android']['apk']['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
