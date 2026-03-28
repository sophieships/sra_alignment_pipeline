FROM ubuntu:24.04

ARG SAMTOOLS_VERSION=1.23.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        libbz2-dev \
        libcurl4-openssl-dev \
        libdeflate-dev \
        liblzma-dev \
        libncurses5-dev \
        perl \
        procps \
        wget \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN wget -q "https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2" && \
    tar -xjf "samtools-${SAMTOOLS_VERSION}.tar.bz2" && \
    cd "samtools-${SAMTOOLS_VERSION}" && \
    make -j"$(nproc)" && \
    make install && \
    rm -rf /tmp/*

WORKDIR /data
