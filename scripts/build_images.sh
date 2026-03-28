#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_CONFIG="${REPO_ROOT}/conf/images.json"
HELPER_SCRIPT="${SCRIPT_DIR}/image_manifest.py"
BUILDER_NAME="sra-pipeline-builder"
DEFAULT_JOBS=2

CONFIG_PATH="${DEFAULT_CONFIG}"
REGISTRY=""
NAMESPACE=""
PLATFORMS=""
PUSH=false
JOBS="${DEFAULT_JOBS}"
TARGETS=""
CHANGED_SINCE=""
CACHE_MODE="local"
CACHE_REF=""
BENCHMARK_FILE=""
LIST_TARGETS=false
LOCAL_CACHE_DIR="${REPO_ROOT}/.buildx-cache"
BENCHMARK_ROW_DIR=""
ATTEMPTED_TARGET_COUNT=0

die() {
    echo "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/build_images.sh [OPTIONS]

Options:
  --config <path>           Image manifest to read (default: conf/images.json)
  --registry <value>        Override the manifest registry
  --namespace <value>       Override the manifest namespace
  --platforms <value>       Comma-separated Docker platforms
  --push                    Push built images to the registry
  --jobs <int>              Max parallel builds (default: 2)
  --targets <list>          Comma-separated subset of image targets
  --changed-since <ref>     Only build targets whose manifest entry, Dockerfile, or build context changed since the git ref
  --cache-mode <mode>       local, registry, or none (default: local)
  --cache-ref <value>       Cache repository override for registry cache mode
  --benchmark-file <path>   Write per-image timing data as CSV
  --list-targets            Print the available build targets and exit
  --help                    Show this message and exit

Examples:
  scripts/build_images.sh
  scripts/build_images.sh --targets qualimap,bowtie2 --jobs 1
  scripts/build_images.sh --push --namespace mydockerhub --cache-mode registry
  scripts/build_images.sh --changed-since origin/main --benchmark-file benchmarks/build_times.csv
EOF
}

require_option_value() {
    local option_name="$1"
    local option_value="${2-}"

    if [[ -z "${option_value}" ]]; then
        die "Option '${option_name}' requires a value."
    fi
}

csv_escape() {
    local value="${1//\"/\"\"}"
    printf '"%s"' "${value}"
}

csv_line() {
    local delimiter=""
    for field in "$@"; do
        printf '%s' "${delimiter}"
        csv_escape "${field}"
        delimiter=","
    done
    printf '\n'
}

build_repository() {
    local image_name="$1"
    local parts=()

    if [[ -n "${REGISTRY}" ]]; then
        parts+=("${REGISTRY}")
    fi
    if [[ -n "${NAMESPACE}" ]]; then
        parts+=("${NAMESPACE}")
    fi
    parts+=("${image_name}")

    local joined=""
    local part
    for part in "${parts[@]}"; do
        if [[ -z "${joined}" ]]; then
            joined="${part}"
        else
            joined="${joined}/${part}"
        fi
    done
    printf '%s\n' "${joined}"
}

build_cache_ref() {
    local target_name="$1"
    local cache_repo="${CACHE_REF}"
    local cache_tag="${target_name//_/-}-buildcache"

    if [[ -z "${cache_repo}" ]]; then
        cache_repo="$(build_repository "sra-alignment-cache")"
    fi

    printf '%s:%s\n' "${cache_repo}" "${cache_tag}"
}

query_manifest() {
    python3 - "$CONFIG_PATH" "$@" <<'PY'
import json
import sys
from json import JSONDecodeError
from pathlib import Path


def require_object(parent, key, path_label):
    value = parent.get(key)
    if not isinstance(value, dict):
        raise SystemExit(f"Manifest field '{path_label}' must be an object: {config_path}")
    return value


def require_string(parent, key, path_label):
    value = parent.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"Manifest field '{path_label}' must be a non-empty string: {config_path}")
    return value.strip()


config_path = Path(sys.argv[1]).expanduser().resolve()
command = sys.argv[2]

try:
    with config_path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
except FileNotFoundError as exc:
    raise SystemExit(f"Manifest file not found: {config_path}") from exc
except JSONDecodeError as exc:
    raise SystemExit(f"Manifest file is not valid JSON: {config_path} ({exc.msg})") from exc

if not isinstance(manifest, dict):
    raise SystemExit(f"Manifest top-level JSON value must be an object: {config_path}")

defaults = require_object(manifest, "defaults", "defaults")

if command == "default-registry":
    print(require_string(defaults, "registry", "defaults.registry"))
elif command == "default-namespace":
    print(require_string(defaults, "namespace", "defaults.namespace"))
elif command == "default-publish-platforms":
    publish_platforms = defaults.get("publish_platforms")
    if not isinstance(publish_platforms, list) or not publish_platforms:
        raise SystemExit(f"Manifest field 'defaults.publish_platforms' must be a non-empty array: {config_path}")

    normalized_platforms = []
    for index, platform in enumerate(publish_platforms):
        if not isinstance(platform, str) or not platform.strip():
            raise SystemExit(
                f"Manifest field 'defaults.publish_platforms[{index}]' must be a non-empty string: {config_path}"
            )
        normalized_platforms.append(platform.strip())

    print(",".join(normalized_platforms))
elif command == "host-platform":
    host_arch = sys.argv[3]
    host_platform_map = require_object(defaults, "host_platform_map", "defaults.host_platform_map")
    resolved_platform = host_platform_map.get(host_arch)
    if not isinstance(resolved_platform, str) or not resolved_platform.strip():
        valid_arches = ", ".join(sorted(host_platform_map))
        raise SystemExit(f"Unsupported host architecture '{host_arch}'. Valid architectures: {valid_arches}")
    print(resolved_platform.strip())
else:
    raise SystemExit(f"Unknown manifest query: {command}")
PY
}

query_manifest_value() {
    local query_name="$1"
    shift

    local manifest_value
    if ! manifest_value="$(query_manifest "${query_name}" "$@" 2>&1)"; then
        die "Failed to read '${query_name}' from image manifest '${CONFIG_PATH}': ${manifest_value}"
    fi

    printf '%s\n' "${manifest_value}"
}

ensure_builder() {
    if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
        echo "Creating buildx builder '${BUILDER_NAME}'..."
        if ! docker buildx create --name "${BUILDER_NAME}" --driver docker-container >/dev/null; then
            echo "Failed to create buildx builder '${BUILDER_NAME}'." >&2
            return 1
        fi
    fi

    if ! docker buildx use "${BUILDER_NAME}" >/dev/null; then
        echo "Failed to select buildx builder '${BUILDER_NAME}'." >&2
        return 1
    fi
    if ! docker buildx inspect --bootstrap "${BUILDER_NAME}" >/dev/null; then
        echo "Failed to bootstrap buildx builder '${BUILDER_NAME}'." >&2
        return 1
    fi
}

wait_for_oldest_job() {
    local oldest_pid="$1"
    local target_name="$2"
    if ! wait "${oldest_pid}"; then
        BUILD_FAILED=1
        echo "Background build failed for target '${target_name}'." >&2
    fi
}

cleanup_benchmark_rows() {
    if [[ -n "${BENCHMARK_ROW_DIR}" && -d "${BENCHMARK_ROW_DIR}" ]]; then
        rm -rf "${BENCHMARK_ROW_DIR}"
    fi
}

write_benchmark_row() {
    local benchmark_row_file="$1"
    local name="$2"
    local image_ref="$3"
    local platforms="$4"
    local output_mode="$5"
    local status="$6"
    local start_epoch="$7"
    local end_epoch="$8"

    if [[ -z "${BENCHMARK_FILE}" || -z "${benchmark_row_file}" ]]; then
        return 0
    fi

    csv_line \
        "image" \
        "${name}" \
        "${image_ref}" \
        "${platforms}" \
        "${CACHE_MODE}" \
        "${output_mode}" \
        "${status}" \
        "${start_epoch}" \
        "${end_epoch}" \
        "$((end_epoch - start_epoch))" \
        "${CHANGED_SINCE}" > "${benchmark_row_file}"
}

build_target() {
    local name="$1"
    local runtime_name="$2"
    local version="$3"
    local dockerfile="$4"
    local context="$5"
    local platforms="$6"
    local build_args_json="$7"
    local benchmark_row_file="$8"

    local output_mode="load"
    if [[ "${PUSH}" == true ]]; then
        output_mode="push"
    fi

    local end_epoch
    local status="success"
    local failure_reason=""
    local image_ref=""
    local start_epoch
    if ! start_epoch="$(date +%s)"; then
        start_epoch=0
        status="failed"
        failure_reason="Failed to record build start time."
    fi

    local image_repository
    if ! image_repository="$(build_repository "${runtime_name}")"; then
        status="failed"
        failure_reason="Failed to resolve image repository for target '${name}'."
    else
        image_ref="${image_repository}:${version}"
    fi

    # Keep per-target build state local so failed setup still yields a benchmark row.
    local -a build_cmd
    build_cmd=(
        docker buildx build
        --builder "${BUILDER_NAME}"
        --platform "${platforms}"
        --tag "${image_ref}"
        --file "${REPO_ROOT}/${dockerfile}"
    )

    local -a cache_flags=()
    case "${CACHE_MODE}" in
        none)
            ;;
        local)
            local cache_dir="${LOCAL_CACHE_DIR}/${name}"
            if ! mkdir -p "${cache_dir}"; then
                status="failed"
                failure_reason="Failed to create local cache directory '${cache_dir}'."
            else
                if [[ -f "${cache_dir}/index.json" ]]; then
                    cache_flags+=(--cache-from "type=local,src=${cache_dir}")
                fi
                cache_flags+=(--cache-to "type=local,dest=${cache_dir},mode=max,ignore-error=true")
            fi
            ;;
        registry)
            local cache_ref
            if ! cache_ref="$(build_cache_ref "${name}")"; then
                status="failed"
                failure_reason="Failed to resolve registry cache reference for target '${name}'."
            elif [[ -z "${cache_ref}" ]]; then
                status="failed"
                failure_reason="Failed to resolve registry cache reference."
            else
                cache_flags+=(
                    --cache-from "type=registry,ref=${cache_ref}"
                    --cache-to "type=registry,ref=${cache_ref},mode=max"
                )
            fi
            ;;
        *)
            status="failed"
            failure_reason="Unsupported cache mode: ${CACHE_MODE}"
            ;;
    esac
    if [[ "${status}" == "success" && ${#cache_flags[@]} -gt 0 ]]; then
        build_cmd+=("${cache_flags[@]}")
    fi

    local -a build_arg_flags=()
    if [[ "${status}" == "success" ]]; then
        local build_arg_lines
        if ! build_arg_lines="$(python3 - "${build_args_json}" 2>&1 <<'PY'
import json
import sys

build_args = json.loads(sys.argv[1])
if not isinstance(build_args, dict):
    raise SystemExit("build args JSON must decode to an object")

for key, value in build_args.items():
    if not isinstance(key, str) or not key:
        raise SystemExit("build arg names must be non-empty strings")
    value_str = str(value)
    if "\n" in key or "\n" in value_str:
        raise SystemExit(f"Build arg '{key}' contains a newline, which is not supported.")
    print(f"{key}={value_str}")
PY
        )"; then
            status="failed"
            failure_reason="Failed to parse build args for target '${name}': ${build_arg_lines}"
        else
            while IFS='=' read -r arg_name arg_value; do
                [[ -z "${arg_name}" ]] && continue
                build_arg_flags+=(--build-arg "${arg_name}=${arg_value}")
            done <<< "${build_arg_lines}"
        fi
    fi
    if [[ "${status}" == "success" && ${#build_arg_flags[@]} -gt 0 ]]; then
        build_cmd+=("${build_arg_flags[@]}")
    fi

    if [[ "${PUSH}" == true ]]; then
        build_cmd+=(--push)
    else
        build_cmd+=(--load)
    fi

    build_cmd+=("${REPO_ROOT}/${context}")

    if [[ "${status}" == "success" ]]; then
        echo "=== Building ${image_ref} (${platforms}) ==="
        if ! "${build_cmd[@]}"; then
            status="failed"
            failure_reason="docker buildx build failed for ${image_ref}."
        fi
    fi
    if ! end_epoch="$(date +%s)"; then
        end_epoch="${start_epoch}"
        if [[ "${status}" == "success" ]]; then
            status="failed"
            failure_reason="Failed to record build end time."
        fi
    fi
    write_benchmark_row "${benchmark_row_file}" "${name}" "${image_ref}" "${platforms}" "${output_mode}" "${status}" "${start_epoch}" "${end_epoch}"

    if [[ "${status}" != "success" ]]; then
        if [[ -n "${failure_reason}" ]]; then
            echo "Build target '${name}' failed: ${failure_reason}" >&2
        fi
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            require_option_value "$1" "${2-}"
            CONFIG_PATH="$2"
            shift 2
            ;;
        --registry)
            require_option_value "$1" "${2-}"
            REGISTRY="$2"
            shift 2
            ;;
        --namespace)
            require_option_value "$1" "${2-}"
            NAMESPACE="$2"
            shift 2
            ;;
        --platforms)
            require_option_value "$1" "${2-}"
            PLATFORMS="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --jobs)
            require_option_value "$1" "${2-}"
            JOBS="$2"
            shift 2
            ;;
        --targets)
            require_option_value "$1" "${2-}"
            TARGETS="$2"
            shift 2
            ;;
        --changed-since)
            require_option_value "$1" "${2-}"
            CHANGED_SINCE="$2"
            shift 2
            ;;
        --cache-mode)
            require_option_value "$1" "${2-}"
            CACHE_MODE="$2"
            shift 2
            ;;
        --cache-ref)
            require_option_value "$1" "${2-}"
            CACHE_REF="$2"
            shift 2
            ;;
        --benchmark-file)
            require_option_value "$1" "${2-}"
            BENCHMARK_FILE="$2"
            shift 2
            ;;
        --list-targets)
            LIST_TARGETS=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "Image manifest not found: ${CONFIG_PATH}" >&2
    exit 1
fi

if [[ ! "${JOBS}" =~ ^[0-9]+$ ]] || [[ "${JOBS}" -lt 1 ]]; then
    echo "--jobs must be a positive integer." >&2
    exit 1
fi

case "${CACHE_MODE}" in
    local|registry|none)
        ;;
    *)
        echo "--cache-mode must be one of: local, registry, none." >&2
        exit 1
        ;;
esac

REGISTRY="${REGISTRY:-$(query_manifest_value default-registry)}"
NAMESPACE="${NAMESPACE:-$(query_manifest_value default-namespace)}"

if [[ "${LIST_TARGETS}" == true ]]; then
    python3 "${HELPER_SCRIPT}" list-targets --config "${CONFIG_PATH}"
    exit 0
fi

if [[ -z "${PLATFORMS}" ]]; then
    if [[ "${PUSH}" == true ]]; then
        PLATFORMS="$(query_manifest_value default-publish-platforms)"
    else
        PLATFORMS="$(query_manifest_value host-platform "$(uname -m)")"
    fi
fi

if [[ -z "${PLATFORMS}" ]]; then
    echo "Could not determine a default Docker platform for host architecture: $(uname -m)" >&2
    exit 1
fi

if [[ "${PUSH}" != true && "${PLATFORMS}" == *,* ]]; then
    echo "Local builds can only use a single platform. Use --push for multi-platform builds." >&2
    exit 1
fi

if [[ "${CACHE_MODE}" == "registry" && "${PUSH}" != true && -z "${CACHE_REF}" ]]; then
    echo "Registry cache mode without --push requires an explicit --cache-ref." >&2
    exit 1
fi

if ! TARGET_JSON="$(
    python3 "${HELPER_SCRIPT}" build-targets \
        --config "${CONFIG_PATH}" \
        --targets "${TARGETS}" \
        --changed-since "${CHANGED_SINCE}"
    2>&1
)"; then
    die "Failed to resolve build targets from image manifest '${CONFIG_PATH}': ${TARGET_JSON}"
fi

if ! TARGET_COUNT="$(
    python3 - "${TARGET_JSON}" <<'PY'
import json
import sys
print(len(json.loads(sys.argv[1])))
PY
)"; then
    die "Failed to count resolved build targets."
fi

if [[ "${TARGET_COUNT}" -eq 0 ]]; then
    echo "No build targets matched the current selection."
    exit 0
fi

if ! ensure_builder; then
    die "Docker buildx builder setup failed."
fi

if [[ -n "${BENCHMARK_FILE}" ]]; then
    mkdir -p "$(dirname "${BENCHMARK_FILE}")"
    BENCHMARK_ROW_DIR="$(mktemp -d)"
fi
trap cleanup_benchmark_rows EXIT

TOTAL_START="$(date +%s)"
BUILD_FAILED=0
ACTIVE_PIDS=()
ACTIVE_TARGET_NAMES=()
# Expand the resolved target JSON once so helper failures cannot disappear inside a read loop.
if ! TARGET_ROWS="$(
    python3 - "${TARGET_JSON}" <<'PY'
import json
import sys

targets = json.loads(sys.argv[1])
for target in targets:
    print(
        "\t".join(
            [
                target["name"],
                target["runtime_name"],
                target["version"],
                target["dockerfile"],
                target["context"],
                json.dumps(target["build_args"], separators=(",", ":")),
            ]
        )
    )
PY
)"; then
    die "Failed to prepare build target rows."
fi

while IFS=$'\t' read -r name runtime_name version dockerfile context build_args_json; do
    [[ -z "${name}" ]] && continue

    if (( BUILD_FAILED )); then
        break
    fi

    benchmark_row_file=""
    if [[ -n "${BENCHMARK_FILE}" ]]; then
        benchmark_row_file="${BENCHMARK_ROW_DIR}/${name}.csv"
    fi

    build_target "${name}" "${runtime_name}" "${version}" "${dockerfile}" "${context}" "${PLATFORMS}" "${build_args_json}" "${benchmark_row_file}" &
    target_pid="$!"
    ACTIVE_PIDS+=("${target_pid}")
    ACTIVE_TARGET_NAMES+=("${name}")
    ((ATTEMPTED_TARGET_COUNT += 1))

    while (( ${#ACTIVE_PIDS[@]} >= JOBS )); do
        wait_for_oldest_job "${ACTIVE_PIDS[0]}" "${ACTIVE_TARGET_NAMES[0]}"
        ACTIVE_PIDS=("${ACTIVE_PIDS[@]:1}")
        ACTIVE_TARGET_NAMES=("${ACTIVE_TARGET_NAMES[@]:1}")
        if (( BUILD_FAILED )); then
            break
        fi
    done
done <<< "${TARGET_ROWS}"

while (( ${#ACTIVE_PIDS[@]} > 0 )); do
    wait_for_oldest_job "${ACTIVE_PIDS[0]}" "${ACTIVE_TARGET_NAMES[0]}"
    ACTIVE_PIDS=("${ACTIVE_PIDS[@]:1}")
    ACTIVE_TARGET_NAMES=("${ACTIVE_TARGET_NAMES[@]:1}")
done

TOTAL_END="$(date +%s)"

if [[ -n "${BENCHMARK_FILE}" ]]; then
    {
        csv_line \
            "scope" \
            "target" \
            "image" \
            "platforms" \
            "cache_mode" \
            "output_mode" \
            "status" \
            "start_epoch" \
            "end_epoch" \
            "duration_seconds" \
            "changed_since"
        find "${BENCHMARK_ROW_DIR}" -type f -name '*.csv' -print | sort | while IFS= read -r row_file; do
            cat "${row_file}"
        done
        csv_line \
            "total" \
            "__total__" \
            "__total__" \
            "${PLATFORMS}" \
            "${CACHE_MODE}" \
            "$([[ "${PUSH}" == true ]] && echo "push" || echo "load")" \
            "$([[ "${BUILD_FAILED}" -eq 0 ]] && echo "success" || echo "failed")" \
            "${TOTAL_START}" \
            "${TOTAL_END}" \
            "$((TOTAL_END - TOTAL_START))" \
            "${CHANGED_SINCE}"
    } > "${BENCHMARK_FILE}"
    echo "Benchmark results written to ${BENCHMARK_FILE}"
fi

echo "Attempted ${ATTEMPTED_TARGET_COUNT} of ${TARGET_COUNT} resolved target(s) in $((TOTAL_END - TOTAL_START))s."

if (( BUILD_FAILED )); then
    echo "One or more image builds failed." >&2
    exit 1
fi
