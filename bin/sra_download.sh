#!/usr/bin/env bash

set -u

accession="$1"

echo "$accession"

base="ftp://ftp.sra.ebi.ac.uk/vol1/fastq"
subdir1="${accession:0:6}"
subdir2="0${accession: -2}"
subdir3="${accession}"

ftp_link_1="${base}/${subdir1}/${subdir2}/${accession}/${accession}_1.fastq.gz"
ftp_link_2="${base}/${subdir1}/${subdir2}/${accession}/${accession}_2.fastq.gz"
ftp_link_3="${base}/${subdir1}/${subdir3}/${accession}_1.fastq.gz"
ftp_link_4="${base}/${subdir1}/${subdir3}/${accession}_2.fastq.gz"
echo "Trying to download $accession from:"
echo "$ftp_link_1"
echo "$ftp_link_2"
echo "$ftp_link_3"
echo "$ftp_link_4"

download_mate() {
    local target="$1"
    local primary_url="$2"
    local alternate_url="$3"

    if [[ -s "$target" && ! -e "${target}.aria2" ]]; then
        echo "File ${target} already exists, download not attempted."
        return 0
    fi

    rm -f "$target" "${target}.aria2"
    if aria2c -x3 -s3 "$primary_url" && [[ -s "$target" && ! -e "${target}.aria2" ]]; then
        return 0
    fi

    echo "Download from ${primary_url} failed"
    rm -f "$target" "${target}.aria2"
    if aria2c -x3 -s3 "$alternate_url" && [[ -s "$target" && ! -e "${target}.aria2" ]]; then
        return 0
    fi

    echo "Download from ${alternate_url} failed"
    rm -f "$target" "${target}.aria2"
    return 1
}

forward_ok=false
reverse_ok=false
if download_mate "${accession}_1.fastq.gz" "$ftp_link_1" "$ftp_link_3"; then
    forward_ok=true
fi
if download_mate "${accession}_2.fastq.gz" "$ftp_link_2" "$ftp_link_4"; then
    reverse_ok=true
fi

status_file="${accession}.txt"
if [[ "$forward_ok" == true && "$reverse_ok" == true ]]; then
    rm -f "$status_file"
else
    rm -f "${accession}_1.fastq.gz" "${accession}_1.fastq.gz.aria2"
    rm -f "${accession}_2.fastq.gz" "${accession}_2.fastq.gz.aria2"
    printf 'ENA download unavailable; use SRA Toolkit fallback for %s\n' "$accession" > "$status_file"
fi
