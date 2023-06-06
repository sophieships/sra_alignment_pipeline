#!/bin/bash

accession="$1"
email="$2"

echo "accession"

base="ftp://ftp.sra.ebi.ac.uk/vol1/fastq"
subdir1="${accession:0:6}"
subdir2="0${accession: -2}"
subdir3="${accession}"

ftp_link_1="${base}/${subdir1}/${subdir2}/${accession}/${accession}_1.fastq.gz"
ftp_link_2="${base}/${subdir1}/${subdir2}/${accession}/${accession}_2.fastq.gz"
ftp_link_3="${base}/${subdir1}/${subdir3}/${accession}_1.fastq.gz"
ftp_link_4="${base}/${subdir1}/${subdir3}/${accession}_2.fastq.gz"
echo "Trying to download $srr from:"
echo "$ftp_link_1"
echo "$ftp_link_2"
echo "$ftp_link_3"
echo "$ftp_link_4"

if [ ! -f "${accession}_1.fastq.gz" ]; then
    aria2c -x3 -s3 "$ftp_link_1" || echo "Download from ${ftp_link_1} failed"
else
    echo "File ${accession}_1.fastq.gz already exists, download not attempted."
fi

if [ ! -f "${accession}_2.fastq.gz" ]; then
    aria2c -x3 -s3 "$ftp_link_2" || echo "Download from ${ftp_link_2} failed"
else
    echo "File ${accession}_2.fastq.gz already exists, download not attempted."
fi

if [ ! -f "${accession}_1.fastq.gz" ]; then
    aria2c -x3 -s3 "$ftp_link_3" || echo "Download from ${ftp_link_3} failed"
else
    echo "File ${accession}_1.fastq.gz already exists, download not attempted."
fi

if [ ! -f "${accession}_2.fastq.gz" ]; then
    aria2c -x3 -s3 "$ftp_link_4" || echo "Download from ${ftp_link_4} failed"
else
    echo "File ${accession}_2.fastq.gz already exists, download not attempted."
fi

if [ ! -f "${accession}_1.fastq.gz" ]; then
    echo "Download failed for ${accession}" > ${accession}_download_status.txt
fi