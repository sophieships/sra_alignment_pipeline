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

default_outdir="$test_root/default-output"
default_log="$test_root/default-cache.log"
nextflow run "$repo_root/main.nf" \
    --input_file "$repo_root/test_data/phage_smoke.csv" \
    --cpus 1 \
    --email test@example.com \
    --outdir "$default_outdir" \
    -profile docker \
    -stub-run \
    -work-dir "$test_root/default-work" \
    -ansi-log false 2>&1 | tee "$default_log"

grep -Fq "Using reference genome cache at ${default_outdir}/reference_genomes" "$default_log"
[[ -e "$default_outdir/reference_genomes/NC_000866.4_reference.fasta.gz" ]] || {
    echo "The implicit reference cache was not created beneath --outdir." >&2
    exit 1
}

jq -e '.["$defs"].output_options.properties.reference_cache.type == "string"' \
    "$repo_root/nextflow_schema.json" >/dev/null
if grep -rn 'results/' "$repo_root/nf_scripts"; then
    echo "Found a hard-coded results/ path in nf_scripts." >&2
    exit 1
fi

echo "Implicit and shared reference cache behavior verified."
