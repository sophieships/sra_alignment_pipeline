FROM ubuntu:24.04

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

WORKDIR /data
