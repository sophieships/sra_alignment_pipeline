ARG PYTHON_IMAGE=python:3.13-slim-bookworm
FROM ${PYTHON_IMAGE}

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential procps && \
    rm -rf /var/lib/apt/lists/*

ARG BIOPYTHON_VERSION=1.86
ARG PYSAM_VERSION=0.23.3

RUN pip install --no-cache-dir "biopython==${BIOPYTHON_VERSION}" "pysam==${PYSAM_VERSION}"

COPY scripts/download_fasta.py /scripts/download_fasta.py

WORKDIR /data
