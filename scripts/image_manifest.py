#!/usr/bin/env python3
"""Query the tracked container image manifest used by the pipeline."""

import argparse
import json
import subprocess
import sys
from json import JSONDecodeError
from pathlib import Path
from typing import Optional


def load_manifest(config_path: str) -> dict:
    """Load the manifest JSON from disk and return it as a dictionary."""
    config_file = Path(config_path).expanduser().resolve()
    try:
        with config_file.open("r", encoding="utf-8") as handle:
            manifest = json.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit(f"Manifest file not found: {config_file}") from exc
    except JSONDecodeError as exc:
        raise SystemExit(f"Manifest file is not valid JSON: {config_file} ({exc.msg})") from exc

    if not isinstance(manifest, dict):
        raise SystemExit(f"Manifest top-level JSON value must be an object: {config_file}")

    return manifest


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").strip("/")


def has_git_head() -> bool:
    """Return True when the current repository has at least one commit."""
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def run_git_command(args: list[str]) -> list[str]:
    """Run a git command and return trimmed non-empty output lines."""
    try:
        result = subprocess.run(
            args,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        detail = stderr or f"exit status {exc.returncode}"
        raise SystemExit(f"Git command failed: {' '.join(args)} ({detail})") from exc

    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def gather_changed_files(changed_since: Optional[str]) -> set[str]:
    """Collect tracked and untracked file changes relevant to target selection."""
    changed_files: set[str] = set()
    repo_has_head = has_git_head()

    if changed_since and repo_has_head:
        changed_files.update(run_git_command(["git", "diff", "--name-only", f"{changed_since}...HEAD"]))

    if repo_has_head:
        changed_files.update(run_git_command(["git", "diff", "--name-only", "HEAD"]))
    changed_files.update(run_git_command(["git", "ls-files", "--others", "--exclude-standard"]))
    return {normalize_path(path) for path in changed_files}


def path_matches_candidate(changed_file: str, candidate: str) -> bool:
    """Match a changed path to a Docker build context or Dockerfile path."""
    normalized_candidate = normalize_path(candidate)
    return changed_file == normalized_candidate or changed_file.startswith(f"{normalized_candidate}/")


def build_targets(
    manifest: dict,
    config_path: str,
    selected_targets: Optional[list[str]],
    changed_since: Optional[str],
) -> list[dict]:
    """Return the enabled manifest targets, optionally filtered by selection or git changes."""
    images = manifest.get("images", {})
    available_targets = {
        name: image
        for name, image in images.items()
        if image.get("build", {}).get("enabled", False)
    }

    if selected_targets:
        disabled_targets = sorted(name for name in set(selected_targets) if name in images and name not in available_targets)
        unknown_targets = sorted(set(selected_targets) - set(images))
        if disabled_targets or unknown_targets:
            error_parts = []
            if disabled_targets:
                error_parts.append(f"Disabled build target(s): {', '.join(disabled_targets)}")
            if unknown_targets:
                error_parts.append(f"Unknown build target(s): {', '.join(unknown_targets)}")
            raise SystemExit(". ".join(error_parts))
        target_names = selected_targets
    else:
        target_names = list(available_targets.keys())

    if changed_since:
        changed_files = gather_changed_files(changed_since)
        manifest_path = normalize_path(config_path)
        if manifest_path in changed_files:
            changed_target_names = target_names
        else:
            changed_target_names = [
                name
                for name in target_names
                if any(
                    path_matches_candidate(changed_file, candidate)
                    for changed_file in changed_files
                    for candidate in (
                        available_targets[name]["build"]["context"],
                        available_targets[name]["build"]["dockerfile"],
                    )
                )
            ]
        target_names = changed_target_names

    return [
        {
            "name": name,
            "runtime_name": available_targets[name]["runtime_name"],
            "version": available_targets[name]["version"],
            "dockerfile": available_targets[name]["build"]["dockerfile"],
            "context": available_targets[name]["build"]["context"],
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
        targets = build_targets(manifest, args.config, None, None)
        for target in targets:
            print(target["name"])
        return 0

    selected_targets = [value.strip() for value in args.targets.split(",") if value.strip()]
    changed_since = args.changed_since.strip() or None
    targets = build_targets(manifest, args.config, selected_targets or None, changed_since)
    json.dump(targets, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
