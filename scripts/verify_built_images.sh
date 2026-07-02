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

    # Resolve the built image reference from the manifest defaults (matches what
    # scripts/build_images.sh tags), not a hardcoded personal namespace.
    local registry namespace
    registry="$(python3 "${SCRIPT_DIR}/image_manifest.py" default-value --config "${CONFIG_PATH}" --field registry)"
    namespace="$(python3 "${SCRIPT_DIR}/image_manifest.py" default-value --config "${CONFIG_PATH}" --field namespace)"
    image_ref="${registry}/${namespace}/${runtime_name}:${version}"

    # The manifest `version` is the biocontainer tag (e.g. 1.23.1--hb2cee57_0);
    # the tool's own --version reports just the upstream version compiled from the
    # build args, so strip the biocontainer build suffix for the expected text.
    local expected_version="${version%%--*}"

    case "${target}" in
        bcftools)
            version_command='bcftools --version | head -n1'
            expected_text="bcftools ${expected_version}"
            ;;
        fastp)
            version_command='fastp --version'
            expected_text="fastp ${expected_version}"
            ;;
        samtools)
            version_command='samtools --version | head -n1'
            expected_text="samtools ${expected_version}"
            ;;
        *)
            echo "Unsupported verification target: ${target} (only from-source buildable tools are supported: bcftools, fastp, samtools)" >&2
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
