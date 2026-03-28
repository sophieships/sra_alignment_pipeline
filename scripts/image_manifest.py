#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional


def load_manifest(config_path: str) -> dict:
    config_file = Path(config_path).expanduser().resolve()
    with config_file.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").strip("/")


def run_git_command(args: list[str]) -> list[str]:
    result = subprocess.run(
        args,
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def gather_changed_files(changed_since: Optional[str]) -> set[str]:
    changed_files: set[str] = set()

    if changed_since:
        changed_files.update(run_git_command(["git", "diff", "--name-only", f"{changed_since}...HEAD"]))

    changed_files.update(run_git_command(["git", "diff", "--name-only", "HEAD"]))
    changed_files.update(run_git_command(["git", "ls-files", "--others", "--exclude-standard"]))
    return {normalize_path(path) for path in changed_files}


def build_targets(manifest: dict, selected_targets: Optional[list[str]], changed_since: Optional[str]) -> list[dict]:
    images = manifest.get("images", {})
    available_targets = {
        name: image
        for name, image in images.items()
        if image.get("build", {}).get("enabled", False)
    }

    if selected_targets:
        unknown_targets = sorted(set(selected_targets) - set(available_targets))
        if unknown_targets:
            raise SystemExit(f"Unknown build target(s): {', '.join(unknown_targets)}")
        target_names = selected_targets
    else:
        target_names = list(available_targets.keys())

    if changed_since:
        changed_files = gather_changed_files(changed_since)
        target_names = [
            name
            for name in target_names
            if any(
                changed_file.startswith(normalize_path(candidate))
                for changed_file in changed_files
                for candidate in (
                    available_targets[name]["build"]["context"],
                    available_targets[name]["build"]["dockerfile"],
                )
            )
        ]

    return [
        {
            "name": name,
            "runtime_name": available_targets[name]["runtime_name"],
            "version": available_targets[name]["version"],
            "dockerfile": available_targets[name]["build"]["dockerfile"],
            "context": available_targets[name]["build"]["context"],
            "platforms": available_targets[name]["build"].get("platforms", []),
            "build_args": available_targets[name]["build"].get("args", {}),
        }
        for name in target_names
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Query the tracked container image manifest.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_targets_parser = subparsers.add_parser("build-targets", help="Return buildable targets as JSON.")
    build_targets_parser.add_argument("--config", required=True, help="Path to the image manifest JSON file.")
    build_targets_parser.add_argument(
        "--targets",
        default="",
        help="Comma-separated subset of targets to include.",
    )
    build_targets_parser.add_argument(
        "--changed-since",
        default="",
        help="Only include targets whose build context changed since the provided git ref.",
    )

    list_parser = subparsers.add_parser("list-targets", help="Print buildable target names.")
    list_parser.add_argument("--config", required=True, help="Path to the image manifest JSON file.")

    args = parser.parse_args()
    manifest = load_manifest(args.config)

    if args.command == "list-targets":
        targets = build_targets(manifest, None, None)
        for target in targets:
            print(target["name"])
        return 0

    selected_targets = [value.strip() for value in args.targets.split(",") if value.strip()]
    changed_since = args.changed_since.strip() or None
    targets = build_targets(manifest, selected_targets or None, changed_since)
    json.dump(targets, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
