#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${REPO_ROOT}/conf/images.json"

if [[ $# -lt 1 ]]; then
    echo "Usage: scripts/verify_built_images.sh <target> [<target> ...]" >&2
    exit 1
fi

manifest_field() {
    local field="$1"
    local target="$2"

    python3 - "${CONFIG_PATH}" "${target}" "${field}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
target = sys.argv[2]
field = sys.argv[3]
manifest = json.loads(config_path.read_text(encoding="utf-8"))
image = manifest["images"][target]

if field == "runtime_name":
    print(image["runtime_name"])
elif field == "version":
    print(image["version"])
else:
    raise SystemExit(f"Unknown manifest field: {field}")
PY
}

verify_target() {
    local target="$1"
    local runtime_name
    local version
    local image_ref
    local version_command
    local expected_text

    runtime_name="$(manifest_field runtime_name "${target}")"
    version="$(manifest_field version "${target}")"
    image_ref="docker.io/eoksen/${runtime_name}:${version}"

    case "${target}" in
        aria2)
            version_command='aria2c --version | head -n1'
            expected_text="aria2 version ${version}"
            ;;
        bcftools)
            version_command='bcftools --version | head -n1'
            expected_text="bcftools ${version}"
            ;;
        fastp)
            version_command='fastp --version'
            expected_text="fastp ${version}"
            ;;
        samtools)
            version_command='samtools --version | head -n1'
            expected_text="samtools ${version}"
            ;;
        *)
            echo "Unsupported verification target: ${target}" >&2
            exit 1
            ;;
    esac

    echo "=== Building ${target} ==="
    "${REPO_ROOT}/scripts/build_images.sh" --targets "${target}" --jobs 1 --cache-mode none

    local version_output
    version_output="$(docker run --rm "${image_ref}" sh -lc "${version_command}")"
    if [[ "${version_output}" != *"${expected_text}"* ]]; then
        echo "Expected ${target} version output to contain: ${expected_text}" >&2
        echo "Actual output:" >&2
        echo "${version_output}" >&2
        exit 1
    fi

    local image_size
    image_size="$(docker image inspect "${image_ref}" --format '{{.Size}}')"
    echo "${target}: ${version_output}"
    echo "${target}: local_image_size_bytes=${image_size}"
}

for target in "$@"; do
    verify_target "${target}"
done
