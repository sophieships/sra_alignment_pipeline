FROM ubuntu:24.04 AS builder

ARG BCFTOOLS_VERSION=1.23.1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        gnuplot \
        libbz2-dev \
        libcurl4-openssl-dev \
        liblzma-dev \
        libncurses5-dev \
        m4 \
        perl \
        procps \
        python3 \
        python3-matplotlib \
        texlive-fonts-recommended \
        texlive-latex-base \
        texlive-latex-extra \
        wget \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN wget -q "https://github.com/samtools/bcftools/releases/download/${BCFTOOLS_VERSION}/bcftools-${BCFTOOLS_VERSION}.tar.bz2" && \
    tar -xjf "bcftools-${BCFTOOLS_VERSION}.tar.bz2" && \
    cd "bcftools-${BCFTOOLS_VERSION}" && \
    make -j"$(nproc)" && \
    make install && \
    rm -rf /tmp/*

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        gnuplot \
        libbz2-1.0 \
        libcurl4t64 \
        liblzma5 \
        perl \
        python3 \
        python3-matplotlib \
        texlive-fonts-recommended \
        texlive-latex-base \
        texlive-latex-extra \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local /usr/local
COPY LICENSE.txt /licenses/bcftools/LICENSE.txt

WORKDIR /data
