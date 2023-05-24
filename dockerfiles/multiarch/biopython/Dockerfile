FROM python:3.9-slim-buster

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

RUN pip install biopython==1.81 pysam==0.21.0

COPY scripts/download_fasta.py /scripts/download_fasta.py

WORKDIR /data

