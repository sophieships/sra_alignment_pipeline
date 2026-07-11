#!/usr/bin/env bash
set -euo pipefail

identifier="$1"
counter_file="${REFERENCE_DOWNLOAD_COUNTER:?REFERENCE_DOWNLOAD_COUNTER must be set}"
count=0
if [[ -f "$counter_file" ]]; then
    read -r count < "$counter_file"
fi
printf '%s\n' "$((count + 1))" > "$counter_file"
printf '>stub-reference\nACGT\n' | gzip > "${identifier}_reference.fasta.gz"
