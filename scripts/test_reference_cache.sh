#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

shared_cache="$test_root/shared-reference-cache"
counter_file="$test_root/download-count"
export REFERENCE_DOWNLOAD_COUNTER="$counter_file"
export PATH="$repo_root/tests/reference_cache/bin:$PATH"

run_pipeline() {
    local outdir="$1"
    nextflow -C "$repo_root/tests/reference_cache/nextflow.config" \
        run "$repo_root/tests/reference_cache/main.nf" \
        --reference_cache "$shared_cache" \
        --outdir "$outdir" \
        -work-dir "$test_root/work" \
        -ansi-log false
}

run_pipeline "$test_root/run-a"
[[ "$(< "$counter_file")" == "1" ]]
[[ -s "$shared_cache/NC_TEST.1_reference.fasta.gz" ]]

run_pipeline "$test_root/run-b"
[[ "$(< "$counter_file")" == "1" ]] || {
    echo "Reference downloader ran more than once despite a shared --reference_cache." >&2
    exit 1
}

jq -e '.["$defs"].output_options.properties.reference_cache.type == "string"' \
    "$repo_root/nextflow_schema.json" >/dev/null
grep -Fq 'reference_cache = "${params.outdir}/reference_genomes"' "$repo_root/main.nf"
grep -Fq 'storeDir params.reference_cache' "$repo_root/nf_scripts/download_fasta.nf"
if grep -rn 'results/' "$repo_root/nf_scripts"; then
    echo "Found a hard-coded results/ path in nf_scripts." >&2
    exit 1
fi

echo "Reference cache reused across distinct output directories."
