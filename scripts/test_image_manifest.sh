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

expect_output_equals() {
    local expected_output="$1"
    shift

    local output
    output="$("$@")"
    if [[ "${output}" != "${expected_output}" ]]; then
        echo "Expected output to equal:" >&2
        printf '%s\n' "${expected_output}" >&2
        echo "Actual output:" >&2
        printf '%s\n' "${output}" >&2
        exit 1
    fi
}

expect_output_contains() {
    local expected_text="$1"
    shift

    local output
    output="$("$@")"
    if [[ "${output}" != *"${expected_text}"* ]]; then
        echo "Expected output to contain: ${expected_text}" >&2
        echo "Actual output:" >&2
        echo "${output}" >&2
        exit 1
    fi
}

expect_json_array_length() {
    local expected_length="$1"
    local json_payload="$2"

    local actual_length
    actual_length="$(python3 - "${json_payload}" <<'PY'
import json
import sys

print(len(json.loads(sys.argv[1])))
PY
)"

    if [[ "${actual_length}" != "${expected_length}" ]]; then
        echo "Expected JSON array length ${expected_length}, got ${actual_length}" >&2
        echo "Payload:" >&2
        echo "${json_payload}" >&2
        exit 1
    fi
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT

cd "${REPO_ROOT}"

expected_targets=$'aria2\nbcftools\nbiopython\nbowtie2\nfastp\npigz\nqualimap\nsamtools\nsra_parser\nsra_tools'
expect_output_equals \
    "${expected_targets}" \
    python3 scripts/image_manifest.py list-targets --config conf/images.json
expect_output_equals \
    "${expected_targets}" \
    scripts/build_images.sh --list-targets
expect_output_equals \
    "docker.io" \
    python3 scripts/image_manifest.py default-value --config conf/images.json --field registry
expect_output_equals \
    "eoksen" \
    python3 scripts/image_manifest.py default-value --config conf/images.json --field namespace
expect_output_equals \
    "linux/amd64,linux/arm64" \
    python3 scripts/image_manifest.py default-value --config conf/images.json --field publish-platforms
expect_output_equals \
    "linux/arm64" \
    python3 scripts/image_manifest.py default-value --config conf/images.json --field host-platform --host-arch arm64

fastp_target_output="$(python3 scripts/image_manifest.py build-targets --config conf/images.json --targets fastp)"
expect_output_contains \
    '"name": "fastp"' \
    python3 scripts/image_manifest.py build-targets --config conf/images.json --targets fastp
expect_output_contains \
    '"dockerfile": "dockerfiles/multiarch/fastp/Dockerfile"' \
    python3 scripts/image_manifest.py build-targets --config conf/images.json --targets fastp

deduped_targets_output="$(python3 scripts/image_manifest.py build-targets --config conf/images.json --targets fastp,fastp)"
expect_json_array_length "1" "${deduped_targets_output}"
if [[ "${deduped_targets_output}" != *'"name": "fastp"'* ]]; then
    echo "Expected de-duplicated target output to contain fastp, got: ${deduped_targets_output}" >&2
    exit 1
fi

fastp_target_rows="$(python3 scripts/image_manifest.py build-target-rows --config conf/images.json --targets fastp)"
expect_output_contains \
    $'fastp\tfastp\t1.3.0\tdockerfiles/multiarch/fastp/Dockerfile\tdockerfiles/multiarch/fastp\t{"FASTP_VERSION":"v1.3.0","LIBISAL_VERSION":"v2.31.1","LIBDEFLATE_VERSION":"v1.25"}' \
    python3 scripts/image_manifest.py build-target-rows --config conf/images.json --targets fastp
if [[ "${fastp_target_rows}" != *$'fastp\tfastp\t1.3.0'* ]]; then
    echo "Expected target row output to contain fastp row, got: ${fastp_target_rows}" >&2
    exit 1
fi

build_arg_lines_output="$(python3 scripts/image_manifest.py build-arg-lines --build-args-json '{"FASTP_VERSION":"v1.3.0","LIBISAL_VERSION":"v2.31.1"}')"
if [[ "${build_arg_lines_output}" != *$'FASTP_VERSION=v1.3.0'* ]] || [[ "${build_arg_lines_output}" != *$'LIBISAL_VERSION=v2.31.1'* ]]; then
    echo "Expected build arg lines output to contain serialized build args, got: ${build_arg_lines_output}" >&2
    exit 1
fi

expect_failure_contains \
    "Option '--jobs' requires a value." \
    scripts/build_images.sh --jobs
expect_failure_contains \
    "--jobs must be a positive integer." \
    scripts/build_images.sh --jobs 0
expect_failure_contains \
    "--jobs must be a positive integer." \
    scripts/build_images.sh --jobs abc
expect_failure_contains \
    "--cache-mode must be one of: local, registry, none." \
    scripts/build_images.sh --cache-mode invalid
expect_failure_contains \
    "Registry cache mode without --push requires an explicit --cache-ref." \
    scripts/build_images.sh --cache-mode registry
expect_failure_contains \
    "Local builds can only use a single platform. Use --push for multi-platform builds." \
    scripts/build_images.sh --platforms linux/amd64,linux/arm64
expect_failure_contains \
    "Unknown option: --nope" \
    scripts/build_images.sh --nope

missing_config="${tmp_root}/missing.json"
expect_failure_contains \
    "Manifest file not found" \
    python3 scripts/image_manifest.py list-targets --config "${missing_config}"
expect_failure_contains \
    "Image manifest not found" \
    scripts/build_images.sh --config "${missing_config}" --list-targets

bad_json="${tmp_root}/bad.json"
printf '{bad json\n' > "${bad_json}"
expect_failure_contains \
    "Manifest file is not valid JSON" \
    python3 scripts/image_manifest.py list-targets --config "${bad_json}"

invalid_utf8_manifest="${tmp_root}/invalid-utf8.json"
printf '\377\376\000\000' > "${invalid_utf8_manifest}"
expect_failure_contains \
    "Manifest file is not valid UTF-8" \
    python3 scripts/image_manifest.py list-targets --config "${invalid_utf8_manifest}"
expect_failure_contains \
    "Failed to read 'registry' from image manifest" \
    scripts/build_images.sh --config "${invalid_utf8_manifest}"

permission_manifest="${tmp_root}/permission.json"
printf '{"defaults":{"registry":"docker.io","namespace":"ns"}}\n' > "${permission_manifest}"
chmod 000 "${permission_manifest}"
expect_failure_contains \
    "Failed to read manifest file" \
    python3 scripts/image_manifest.py list-targets --config "${permission_manifest}"
expect_failure_contains \
    "Failed to read 'registry' from image manifest" \
    scripts/build_images.sh --config "${permission_manifest}"
chmod 600 "${permission_manifest}"

non_object_manifest="${tmp_root}/non-object.json"
printf '[1, 2, 3]\n' > "${non_object_manifest}"
expect_failure_contains \
    "Manifest top-level JSON value must be an object" \
    python3 scripts/image_manifest.py list-targets --config "${non_object_manifest}"

missing_images_manifest="${tmp_root}/missing-images.json"
cat > "${missing_images_manifest}" <<'JSON'
{"defaults":{"registry":"docker.io","namespace":"ns"}}
JSON
expect_failure_contains \
    "Manifest field 'images' must be an object" \
    python3 scripts/image_manifest.py list-targets --config "${missing_images_manifest}"

images_not_object_manifest="${tmp_root}/images-not-object.json"
cat > "${images_not_object_manifest}" <<'JSON'
{"defaults":{"registry":"docker.io","namespace":"ns"},"images":[]}
JSON
expect_failure_contains \
    "Manifest field 'images' must be an object" \
    python3 scripts/image_manifest.py list-targets --config "${images_not_object_manifest}"

disabled_manifest="${tmp_root}/disabled.json"
cat > "${disabled_manifest}" <<'JSON'
{"images":{"enabled_one":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"a","context":"a"}},"disabled_one":{"runtime_name":"bar","version":"1","build":{"enabled":false,"dockerfile":"b","context":"b"}}}}
JSON
expect_output_equals \
    "enabled_one" \
    python3 scripts/image_manifest.py list-targets --config "${disabled_manifest}"

list_targets_manifest="${tmp_root}/list-targets.json"
cat > "${list_targets_manifest}" <<'JSON'
{"images":{"foo":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"dockerfiles/foo/Dockerfile","context":"dockerfiles/foo"}}}}
JSON
expect_output_equals \
    "foo" \
    scripts/build_images.sh --list-targets --config "${list_targets_manifest}"

expect_failure_contains \
    "Disabled build target(s): disabled_one" \
    python3 scripts/image_manifest.py build-targets --config "${disabled_manifest}" --targets disabled_one

expect_failure_contains \
    "Unknown build target(s): missing_one" \
    python3 scripts/image_manifest.py build-targets --config "${disabled_manifest}" --targets missing_one

missing_context_manifest="${tmp_root}/missing-context.json"
cat > "${missing_context_manifest}" <<'JSON'
{"images":{"foo":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"dockerfiles/foo/Dockerfile"}}}}
JSON
expect_failure_contains \
    "Manifest field 'images.foo.build.context' must be a non-empty string" \
    python3 scripts/image_manifest.py build-targets --config "${missing_context_manifest}" --targets foo

expect_failure_contains \
    "Build args payload is not valid JSON" \
    python3 scripts/image_manifest.py build-arg-lines --build-args-json '{bad json'

warning_bin="${tmp_root}/warning-bin"
mkdir -p "${warning_bin}"
cat > "${warning_bin}/python3" <<EOF
#!/bin/sh
echo "simulated helper warning" >&2
exec "$(command -v python3)" "\$@"
EOF
chmod +x "${warning_bin}/python3"

stub_manifest="${tmp_root}/stub-build.json"
mkdir -p "${tmp_root}/stub-context"
cat > "${stub_manifest}" <<'JSON'
{"defaults":{"registry":"docker.io","namespace":"ns","publish_platforms":["linux/amd64"],"host_platform_map":{"arm64":"linux/arm64","x86_64":"linux/amd64"}},"images":{"foo":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"stub-context/Dockerfile","context":"stub-context","args":{"FOO":"BAR"}}}}}
JSON
cat > "${tmp_root}/stub-context/Dockerfile" <<'EOF'
FROM scratch
EOF

docker_stub_bin="${tmp_root}/docker-stub-bin"
mkdir -p "${docker_stub_bin}"
cat > "${docker_stub_bin}/docker" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "info ")
    exit 0
    ;;
  "buildx inspect")
    exit 0
    ;;
  "buildx use")
    exit 0
    ;;
  "buildx build")
    exit 0
    ;;
esac
if [ "$1" = "buildx" ] && [ "$2" = "inspect" ] && [ "$3" = "--bootstrap" ]; then
  exit 0
fi
echo "unexpected docker invocation: $*" >&2
exit 1
EOF
chmod +x "${docker_stub_bin}/docker"

warning_build_output="$(
    env PATH="${warning_bin}:${docker_stub_bin}:${PATH}" \
        scripts/build_images.sh \
        --config "${stub_manifest}" \
        --targets foo \
        --jobs 1 \
        --cache-mode none \
        --platforms linux/amd64
)"
if [[ "${warning_build_output}" != *"=== Building docker.io/ns/foo:1 (linux/amd64) ==="* ]]; then
    echo "Expected clean image ref in build output, got: ${warning_build_output}" >&2
    exit 1
fi
if [[ "${warning_build_output}" == *"simulated helper warning"* ]]; then
    echo "Expected helper stderr warning to stay out of captured build values, got: ${warning_build_output}" >&2
    exit 1
fi

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

absolute_manifest_change_output="$(
    python3 "${REPO_ROOT}/scripts/image_manifest.py" \
        build-targets \
        --config "${manifest_change_dir}/conf/images.json" \
        --changed-since HEAD
)"
if [[ "${absolute_manifest_change_output}" != *'"name": "foo"'* ]]; then
    echo "Expected manifest-only change with absolute config path to include foo target, got: ${absolute_manifest_change_output}" >&2
    exit 1
fi

dockerfile_change_dir="${tmp_root}/dockerfile-change"
mkdir -p "${dockerfile_change_dir}/conf" "${dockerfile_change_dir}/dockerfiles/foo"
cd "${dockerfile_change_dir}"
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
printf '\nLABEL test_change=1\n' >> dockerfiles/foo/Dockerfile
dockerfile_change_output="$(python3 "${REPO_ROOT}/scripts/image_manifest.py" build-targets --config conf/images.json --changed-since HEAD)"
if [[ "${dockerfile_change_output}" != *'"name": "foo"'* ]]; then
    echo "Expected Dockerfile-only change to include foo target, got: ${dockerfile_change_output}" >&2
    exit 1
fi

intersection_dir="${tmp_root}/targets-intersection"
mkdir -p "${intersection_dir}/conf" "${intersection_dir}/dockerfiles/foo" "${intersection_dir}/dockerfiles/bar"
cd "${intersection_dir}"
git init -q
git config user.email "ci@example.com"
git config user.name "CI"
cat > conf/images.json <<'JSON'
{"defaults":{"registry":"docker.io","namespace":"ns"},"images":{"foo":{"runtime_name":"foo","version":"1","build":{"enabled":true,"dockerfile":"dockerfiles/foo/Dockerfile","context":"dockerfiles/foo"}},"bar":{"runtime_name":"bar","version":"1","build":{"enabled":true,"dockerfile":"dockerfiles/bar/Dockerfile","context":"dockerfiles/bar"}}}}
JSON
cat > dockerfiles/foo/Dockerfile <<'EOF'
FROM scratch
EOF
cat > dockerfiles/bar/Dockerfile <<'EOF'
FROM scratch
EOF
git add .
git commit -qm init
printf '\nLABEL changed=1\n' >> dockerfiles/foo/Dockerfile
intersection_output="$(
    python3 "${REPO_ROOT}/scripts/image_manifest.py" \
        build-targets \
        --config conf/images.json \
        --targets foo,bar \
        --changed-since HEAD
)"
expect_json_array_length "1" "${intersection_output}"
if [[ "${intersection_output}" != *'"name": "foo"'* ]] || [[ "${intersection_output}" == *'"name": "bar"'* ]]; then
    echo "Expected --targets with --changed-since to keep only changed selected targets, got: ${intersection_output}" >&2
    exit 1
fi

injection_probe_path="${tmp_root}/git-output.txt"
expect_failure_contains \
    "Git command failed" \
    python3 "${REPO_ROOT}/scripts/image_manifest.py" build-targets --config conf/images.json --changed-since="--output=${injection_probe_path}"
if [[ -e "${injection_probe_path}" ]]; then
    echo "Unexpected file created by git option injection probe: ${injection_probe_path}" >&2
    exit 1
fi

missing_git_bin="${tmp_root}/missing-git-bin"
mkdir -p "${missing_git_bin}"
ln -s "$(command -v python3)" "${missing_git_bin}/python3"
expect_failure_contains \
    "Git is required for --changed-since but was not found on PATH." \
    env PATH="${missing_git_bin}" python3 "${REPO_ROOT}/scripts/image_manifest.py" build-targets --config "${REPO_ROOT}/conf/images.json" --changed-since HEAD
