#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

export PATH="$repo_root/tests/download_fallback/bin:$PATH"

run_ena_download() {
    local mode="$1"
    local run_dir="$2"
    mkdir -p "$run_dir"
    (
        cd "$run_dir"
        ARIA2_TEST_MODE="$mode" "$repo_root/bin/sra_download.sh" SRR_TEST
    )
}

ena_success="$test_root/ena-success"
run_ena_download success "$ena_success"
[[ -s "$ena_success/SRR_TEST_1.fastq.gz" ]]
[[ -s "$ena_success/SRR_TEST_2.fastq.gz" ]]
[[ ! -e "$ena_success/SRR_TEST.txt" ]]

for incomplete_mode in missing-forward missing-reverse missing-both; do
    ena_incomplete="$test_root/ena-${incomplete_mode}"
    run_ena_download "$incomplete_mode" "$ena_incomplete"
    [[ ! -e "$ena_incomplete/SRR_TEST_1.fastq.gz" ]]
    [[ ! -e "$ena_incomplete/SRR_TEST_2.fastq.gz" ]]
    [[ ! -e "$ena_incomplete/SRR_TEST_1.fastq.gz.aria2" ]]
    [[ ! -e "$ena_incomplete/SRR_TEST_2.fastq.gz.aria2" ]]
    grep -Fxq 'ENA download unavailable; use SRA Toolkit fallback for SRR_TEST' \
        "$ena_incomplete/SRR_TEST.txt"
done

status_dir="$test_root/fallback-status"
mkdir -p "$status_dir"
printf 'fallback\n' > "$status_dir/SRR_TEST_A.txt"
printf 'fallback\n' > "$status_dir/SRR_TEST_B.txt"
export FALLBACK_TOOL_LOG="$test_root/tool.log"
export FASTERQ_TEST_MODE=paired

nextflow -C "$repo_root/tests/download_fallback/nextflow.config" \
    run "$repo_root/tests/download_fallback/main.nf" \
    --download_status "$status_dir/*.txt" \
    --outdir "$test_root/fallback-output" \
    -work-dir "$test_root/fallback-work" \
    -ansi-log false

for accession in SRR_TEST_A SRR_TEST_B; do
    [[ -s "$test_root/fallback-output/$accession/fastq/${accession}_1.fastq.gz" ]]
    [[ -s "$test_root/fallback-output/$accession/fastq/${accession}_2.fastq.gz" ]]
    grep -Fq "prefetch $accession" "$FALLBACK_TOOL_LOG"
    grep -Fq "fasterq-dump $accession --split-files --skip-technical" "$FALLBACK_TOOL_LOG"
    grep -Fq "pigz ${accession}_1.fastq" "$FALLBACK_TOOL_LOG"
    grep -Fq "pigz ${accession}_2.fastq" "$FALLBACK_TOOL_LOG"
done

export FASTERQ_TEST_MODE=single-end
if single_end_output="$(nextflow -C "$repo_root/tests/download_fallback/nextflow.config" \
    run "$repo_root/tests/download_fallback/main.nf" \
    --download_status "$status_dir/SRR_TEST_A.txt" \
    --outdir "$test_root/single-end-output" \
    -work-dir "$test_root/single-end-work" \
    -ansi-log false 2>&1)"; then
    echo "Expected a single-end fallback result to fail." >&2
    exit 1
fi
[[ "$single_end_output" == *"single-end input is not supported"* ]] || {
    echo "$single_end_output" >&2
    exit 1
}

echo "ENA success, incomplete-pair fallback, and multi-accession fasterq-to-pigz routing verified."
