#!/usr/bin/env python3
"""Validate and query the tracked image manifest for build-targets/list-targets."""

import argparse
import json
import subprocess
import sys
from json import JSONDecodeError
from pathlib import Path
from typing import Any, Optional


def load_manifest(config_path: str) -> tuple[dict[str, Any], Path]:
    """Load the manifest JSON from disk and return the parsed object plus its resolved path."""
    config_file = Path(config_path).expanduser().resolve()
    try:
        with config_file.open("r", encoding="utf-8") as handle:
            manifest = json.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit(f"Manifest file not found: {config_file}") from exc
    except UnicodeDecodeError as exc:
        raise SystemExit(f"Manifest file is not valid UTF-8: {config_file} ({exc})") from exc
    except JSONDecodeError as exc:
        raise SystemExit(f"Manifest file is not valid JSON: {config_file} ({exc.msg})") from exc
    except OSError as exc:
        detail = exc.strerror or str(exc)
        raise SystemExit(f"Failed to read manifest file: {config_file} ({detail})") from exc

    if not isinstance(manifest, dict):
        raise SystemExit(f"Manifest top-level JSON value must be an object: {config_file}")

    return manifest, config_file


def require_object(parent: dict[str, Any], key: str, config_file: Path, path_label: str) -> dict[str, Any]:
    """Return a manifest object member or raise a readable validation error."""
    value = parent.get(key)
    if not isinstance(value, dict):
        raise SystemExit(f"Manifest field '{path_label}' must be an object: {config_file}")
    return value


def require_string(parent: dict[str, Any], key: str, config_file: Path, path_label: str) -> str:
    """Return a non-empty manifest string member or raise a readable validation error."""
    value = parent.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"Manifest field '{path_label}' must be a non-empty string: {config_file}")
    return value.strip()


def require_bool(parent: dict[str, Any], key: str, config_file: Path, path_label: str) -> bool:
    """Return a manifest boolean member or raise a readable validation error."""
    value = parent.get(key)
    if not isinstance(value, bool):
        raise SystemExit(f"Manifest field '{path_label}' must be a boolean: {config_file}")
    return value


def require_image_map(manifest: dict[str, Any], config_file: Path) -> dict[str, Any]:
    """Return the top-level images object."""
    return require_object(manifest, "images", config_file, "images")


def validate_target_definition(name: str, image_definition: Any, config_file: Path) -> dict[str, Any]:
    """Validate one image entry used by build helper commands."""
    if not isinstance(image_definition, dict):
        raise SystemExit(f"Manifest field 'images.{name}' must be an object: {config_file}")

    require_string(image_definition, "runtime_name", config_file, f"images.{name}.runtime_name")
    require_string(image_definition, "version", config_file, f"images.{name}.version")
    build_definition = require_object(image_definition, "build", config_file, f"images.{name}.build")
    require_bool(build_definition, "enabled", config_file, f"images.{name}.build.enabled")
    require_string(build_definition, "dockerfile", config_file, f"images.{name}.build.dockerfile")
    require_string(build_definition, "context", config_file, f"images.{name}.build.context")

    build_args = build_definition.get("args", {})
    if not isinstance(build_args, dict):
        raise SystemExit(f"Manifest field 'images.{name}.build.args' must be an object: {config_file}")

    return image_definition


def unique_preserving_order(values: list[str]) -> list[str]:
    """Remove duplicates while preserving the first-seen order."""
    deduped: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value not in seen:
            seen.add(value)
            deduped.append(value)
    return deduped


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").strip("/")


def git_command_text(args: list[str]) -> str:
    """Return a shell-style label for error messages."""
    return " ".join(args)


def run_git_process(args: list[str], *, check: bool) -> subprocess.CompletedProcess[str]:
    """Run git and return the completed process with consistent launch-error handling."""
    try:
        return subprocess.run(
            args,
            check=check,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("Git is required for --changed-since but was not found on PATH.") from exc
    except OSError as exc:
        detail = exc.strerror or str(exc)
        raise SystemExit(f"Failed to execute git command: {git_command_text(args)} ({detail})") from exc


def ensure_git_repository() -> None:
    """Ensure the current working directory is inside a git repository."""
    result = run_git_process(["git", "rev-parse", "--is-inside-work-tree"], check=False)
    if result.returncode == 0 and result.stdout.strip() == "true":
        return

    stderr = result.stderr.strip().lower()
    if "not a git repository" in stderr:
        raise SystemExit("--changed-since requires running inside a git repository.")

    detail = result.stderr.strip() or f"exit status {result.returncode}"
    raise SystemExit(
        f"Git command failed: {git_command_text(['git', 'rev-parse', '--is-inside-work-tree'])} ({detail})"
    )


def git_repository_root() -> Path:
    """Return the current repository root."""
    resolved_root = run_git_command(["git", "rev-parse", "--show-toplevel"])
    if len(resolved_root) != 1:
        raise SystemExit("Git repository root did not resolve uniquely.")
    return Path(resolved_root[0]).expanduser().resolve()


def has_git_head() -> bool:
    """Return True when the current repository has at least one commit."""
    result = run_git_process(["git", "rev-parse", "--verify", "HEAD"], check=False)
    if result.returncode == 0:
        return True

    stderr = result.stderr.strip().lower()
    if "needed a single revision" in stderr or "ambiguous argument 'head'" in stderr:
        return False

    detail = result.stderr.strip() or f"exit status {result.returncode}"
    raise SystemExit(f"Git command failed: {git_command_text(['git', 'rev-parse', '--verify', 'HEAD'])} ({detail})")


def run_git_command(args: list[str]) -> list[str]:
    """Run a git command and return trimmed non-empty output lines."""
    try:
        result = run_git_process(args, check=True)
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        detail = stderr or f"exit status {exc.returncode}"
        raise SystemExit(f"Git command failed: {git_command_text(args)} ({detail})") from exc

    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def resolve_revision(revision: str) -> str:
    """Resolve a user-supplied git revision without allowing option injection."""
    resolved = run_git_command(["git", "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"])
    if len(resolved) != 1:
        raise SystemExit(f"Git revision did not resolve uniquely: {revision}")
    return resolved[0]


def gather_changed_files(changed_since: Optional[str]) -> tuple[set[str], Path]:
    """Collect tracked and untracked file changes relevant to target selection."""
    ensure_git_repository()
    repo_root = git_repository_root()
    changed_files: set[str] = set()
    repo_has_head = has_git_head()

    if changed_since and repo_has_head:
        changed_since_sha = resolve_revision(changed_since)
        changed_files.update(run_git_command(["git", "diff", "--name-only", f"{changed_since_sha}...HEAD", "--"]))

    if repo_has_head:
        changed_files.update(run_git_command(["git", "diff", "--name-only", "HEAD", "--"]))
    changed_files.update(run_git_command(["git", "ls-files", "--others", "--exclude-standard", "--"]))
    return {normalize_path(path) for path in changed_files}, repo_root


def repo_relative_path(path: Path, repo_root: Path) -> Optional[str]:
    """Return a normalized git-relative path when the file is inside the repository."""
    try:
        return normalize_path(str(path.resolve().relative_to(repo_root)))
    except ValueError:
        return None


def path_matches_candidate(changed_file: str, candidate: str) -> bool:
    """Match a changed path to a Docker build context or Dockerfile path."""
    normalized_candidate = normalize_path(candidate)
    return changed_file == normalized_candidate or changed_file.startswith(f"{normalized_candidate}/")


def build_targets(
    manifest: dict[str, Any],
    config_file: Path,
    selected_targets: Optional[list[str]],
    changed_since: Optional[str],
) -> list[dict]:
    """Return the enabled manifest targets, optionally filtered by selection or git changes."""
    images = require_image_map(manifest, config_file)
    validated_images = {
        name: validate_target_definition(name, image_definition, config_file)
        for name, image_definition in images.items()
    }
    available_targets = {
        name: image
        for name, image in validated_images.items()
        if image.get("build", {}).get("enabled", False)
    }

    if selected_targets:
        selected_targets = unique_preserving_order(selected_targets)
        disabled_targets = sorted(name for name in selected_targets if name in validated_images and name not in available_targets)
        unknown_targets = sorted(name for name in selected_targets if name not in validated_images)
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
        changed_files, repo_root = gather_changed_files(changed_since)
        manifest_path = repo_relative_path(config_file, repo_root)
        if manifest_path and manifest_path in changed_files:
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
        help="Only include targets whose manifest entry, Dockerfile, or build context changed since the provided git ref.",
    )

    list_parser = subparsers.add_parser("list-targets", help="Print buildable target names.")
    list_parser.add_argument("--config", required=True, help="Path to the image manifest JSON file.")

    args = parser.parse_args()
    manifest, config_file = load_manifest(args.config)

    if args.command == "list-targets":
        targets = build_targets(manifest, config_file, None, None)
        for target in targets:
            print(target["name"])
        return 0

    selected_targets = [value.strip() for value in args.targets.split(",") if value.strip()]
    changed_since = args.changed_since.strip() or None
    targets = build_targets(manifest, config_file, selected_targets or None, changed_since)
    json.dump(targets, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
