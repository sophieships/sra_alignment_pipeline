#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

expect_failure_contains() {
    local expected_text="$1"
    shift

    local output
    if output="$("$@" 2>&1)"; then
        echo "Expected failure but command succeeded: $*" >&2
        exit 1
    fi

    if [[ "${output}" != *"${expected_text}"* ]]; then
        echo "Expected output to contain: ${expected_text}" >&2
        echo "Actual output:" >&2
        echo "${output}" >&2
        exit 1
    fi
}

expect_output_contains() {
    local expected_text="$1"
    shift

    local output
    output="$("$@" 2>&1)"
    if [[ "${output}" != *"${expected_text}"* ]]; then
        echo "Expected output to contain: ${expected_text}" >&2
        echo "Actual output:" >&2
        echo "${output}" >&2
        exit 1
    fi
}

expect_file_contains() {
    local expected_text="$1"
    local file_path="$2"

    if [[ ! -f "${file_path}" ]]; then
        echo "Expected file to exist: ${file_path}" >&2
        exit 1
    fi

    if ! grep -F --quiet -- "${expected_text}" "${file_path}"; then
        echo "Expected file ${file_path} to contain: ${expected_text}" >&2
        echo "Actual contents:" >&2
        cat "${file_path}" >&2
        exit 1
    fi
}

tmp_root="$(mktemp -d "${REPO_ROOT}/.tmp-build-images-test.XXXXXX")"
trap 'rm -rf "${tmp_root}"' EXIT

docker_stub_bin="${tmp_root}/bin"
mkdir -p "${docker_stub_bin}"
cat > "${docker_stub_bin}/docker" <<'EOF'
#!/bin/sh
set -eu

log_file="${DOCKER_STUB_LOG:-}"
if [ -n "${log_file}" ]; then
    printf '%s\n' "$*" >> "${log_file}"
fi

if [ "${1:-}" = "info" ]; then
    if [ "${DOCKER_INFO_FAIL:-0}" = "1" ]; then
        echo "simulated docker info failure" >&2
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "buildx" ] && [ "${2:-}" = "inspect" ] && [ "${3:-}" != "--bootstrap" ]; then
    if [ "${DOCKER_INSPECT_MISSING:-0}" = "1" ]; then
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "buildx" ] && [ "${2:-}" = "create" ]; then
    if [ "${DOCKER_CREATE_FAIL:-0}" = "1" ]; then
        echo "simulated docker buildx create failure" >&2
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "buildx" ] && [ "${2:-}" = "use" ]; then
    if [ "${DOCKER_USE_FAIL:-0}" = "1" ]; then
        echo "simulated docker buildx use failure" >&2
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "buildx" ] && [ "${2:-}" = "inspect" ] && [ "${3:-}" = "--bootstrap" ]; then
    if [ "${DOCKER_BOOTSTRAP_FAIL:-0}" = "1" ]; then
        echo "simulated docker buildx bootstrap failure" >&2
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "buildx" ] && [ "${2:-}" = "build" ]; then
    tag=""
    prev=""
    for arg in "$@"; do
        if [ "${prev}" = "--tag" ]; then
            tag="${arg}"
            break
        fi
        prev="${arg}"
    done

    if [ -n "${DOCKER_BUILD_SLEEP:-}" ]; then
        sleep "${DOCKER_BUILD_SLEEP}"
    fi

    case ",${DOCKER_FAIL_TAGS:-}," in
        *,"${tag}",*)
            echo "simulated docker build failure for ${tag}" >&2
            exit 1
            ;;
    esac
    exit 0
fi

echo "unexpected docker invocation: $*" >&2
exit 1
EOF
chmod +x "${docker_stub_bin}/docker"

context_dir="${tmp_root}/dockerfiles"
mkdir -p "${context_dir}/foo" "${context_dir}/bar"
cat > "${context_dir}/foo/Dockerfile" <<'EOF'
FROM scratch
EOF
cat > "${context_dir}/bar/Dockerfile" <<'EOF'
FROM scratch
EOF

manifest_path="${tmp_root}/images.json"
cat > "${manifest_path}" <<JSON
{
  "defaults": {
    "registry": "docker.io",
    "namespace": "ns",
    "publish_platforms": ["linux/amd64", "linux/arm64"],
    "host_platform_map": {
      "x86_64": "linux/amd64",
      "arm64": "linux/arm64"
    }
  },
  "images": {
    "foo": {
      "runtime_name": "foo",
      "version": "1",
      "build": {
        "enabled": true,
        "dockerfile": "${tmp_root#"${REPO_ROOT}/"}/dockerfiles/foo/Dockerfile",
        "context": "${tmp_root#"${REPO_ROOT}/"}/dockerfiles/foo",
        "args": {
          "FOO": "BAR"
        }
      }
    },
    "bar": {
      "runtime_name": "bar",
      "version": "1",
      "build": {
        "enabled": true,
        "dockerfile": "${tmp_root#"${REPO_ROOT}/"}/dockerfiles/bar/Dockerfile",
        "context": "${tmp_root#"${REPO_ROOT}/"}/dockerfiles/bar"
      }
    }
  }
}
JSON

cd "${REPO_ROOT}"

expect_failure_contains \
    "Docker daemon is unreachable" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_INFO_FAIL=1 scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode none --platforms linux/amd64

expect_failure_contains \
    "Failed to create buildx builder" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_INSPECT_MISSING=1 DOCKER_CREATE_FAIL=1 scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode none --platforms linux/amd64

expect_failure_contains \
    "Failed to select buildx builder" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_USE_FAIL=1 scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode none --platforms linux/amd64

expect_failure_contains \
    "Failed to bootstrap buildx builder" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_BOOTSTRAP_FAIL=1 scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode none --platforms linux/amd64

registry_cache_log="${tmp_root}/registry-cache.log"
expect_output_contains \
    "Attempted 1 of 1 resolved target(s)" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_STUB_LOG="${registry_cache_log}" scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode registry --cache-ref registry.example/custom-cache --platforms linux/amd64
expect_file_contains "type=registry,ref=registry.example/custom-cache:foo-buildcache" "${registry_cache_log}"
expect_file_contains "--load" "${registry_cache_log}"

push_cache_log="${tmp_root}/push-cache.log"
expect_output_contains \
    "Attempted 1 of 1 resolved target(s)" \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_STUB_LOG="${push_cache_log}" scripts/build_images.sh --config "${manifest_path}" --targets foo --jobs 1 --cache-mode registry --push --platforms linux/amd64,linux/arm64
expect_file_contains "type=registry,ref=docker.io/ns/sra-alignment-cache:foo-buildcache" "${push_cache_log}"
expect_file_contains "--push" "${push_cache_log}"

benchmark_file="${tmp_root}/benchmark.csv"
expect_failure_contains \
    "One or more image builds failed." \
    env PATH="${docker_stub_bin}:${PATH}" DOCKER_BUILD_SLEEP=1 DOCKER_FAIL_TAGS="docker.io/ns/bar:1" scripts/build_images.sh --config "${manifest_path}" --targets foo,bar --jobs 2 --cache-mode none --platforms linux/amd64 --benchmark-file "${benchmark_file}"
expect_file_contains '"image","bar","docker.io/ns/bar:1","linux/amd64","none","load","failed"' "${benchmark_file}"
expect_file_contains '"image","foo","docker.io/ns/foo:1","linux/amd64","none","load","success"' "${benchmark_file}"
expect_file_contains '"total","__total__","__total__","linux/amd64","none","load","failed"' "${benchmark_file}"
