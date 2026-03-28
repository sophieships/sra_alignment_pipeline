FROM ubuntu:24.04 AS builder

ARG SAMTOOLS_VERSION=1.23.1
ENV DEBIAN_FRONTEND=noninteractive

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

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libbz2-1.0 \
        libcurl4t64 \
        libdeflate0 \
        liblzma5 \
        libncurses6 \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/samtools /usr/local/bin/samtools
COPY LICENSE.txt /licenses/samtools/LICENSE.txt

WORKDIR /data
