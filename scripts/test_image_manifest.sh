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

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT

cd "${REPO_ROOT}"

python3 scripts/image_manifest.py list-targets --config conf/images.json >/dev/null
python3 scripts/image_manifest.py build-targets --config conf/images.json --targets fastp >/dev/null
scripts/build_images.sh --list-targets >/dev/null

bad_json="${tmp_root}/bad.json"
printf '{bad json\n' > "${bad_json}"
expect_failure_contains \
    "Manifest file is not valid JSON" \
    python3 scripts/image_manifest.py list-targets --config "${bad_json}"

disabled_manifest="${tmp_root}/disabled.json"
cat > "${disabled_manifest}" <<'JSON'
{"images":{"enabled_one":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"a","context":"a"}},"disabled_one":{"runtime_name":"bar","version":"1","build":{"enabled":false,"dockerfile":"b","context":"b"}}}}
JSON
expect_failure_contains \
    "Disabled build target(s): disabled_one" \
    python3 scripts/image_manifest.py build-targets --config "${disabled_manifest}" --targets disabled_one

empty_repo_dir="${tmp_root}/empty-repo"
mkdir -p "${empty_repo_dir}"
cd "${empty_repo_dir}"
git init -q
empty_repo_output="$(python3 "${REPO_ROOT}/scripts/image_manifest.py" build-targets --config "${REPO_ROOT}/conf/images.json" --changed-since HEAD)"
if [[ "${empty_repo_output}" != "[]" ]]; then
    echo "Expected empty output for empty repo changed-since check, got: ${empty_repo_output}" >&2
    exit 1
fi

manifest_change_dir="${tmp_root}/manifest-change"
mkdir -p "${manifest_change_dir}/conf" "${manifest_change_dir}/dockerfiles/foo"
cd "${manifest_change_dir}"
git init -q
git config user.email "ci@example.com"
git config user.name "CI"
cat > conf/images.json <<'JSON'
{"defaults":{"registry":"docker.io","namespace":"ns"},"images":{"foo":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"dockerfiles/foo/Dockerfile","context":"dockerfiles/foo","args":{"FOO":"1"}}}}}
JSON
cat > dockerfiles/foo/Dockerfile <<'EOF'
FROM scratch
EOF
git add .
git commit -qm init
perl -0pi -e 's/"FOO":"1"/"FOO":"2"/' conf/images.json
manifest_change_output="$(python3 "${REPO_ROOT}/scripts/image_manifest.py" build-targets --config conf/images.json --changed-since HEAD)"
if [[ "${manifest_change_output}" != *'"name": "foo"'* ]]; then
    echo "Expected manifest-only change to include foo target, got: ${manifest_change_output}" >&2
    exit 1
fi
