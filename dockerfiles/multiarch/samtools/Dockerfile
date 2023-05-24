FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    zlib1g-dev \
    libncurses5-dev \
    libbz2-dev \
    liblzma-dev \
    libcurl4-gnutls-dev \
    perl \
    lua5.3

WORKDIR /tmp

RUN wget https://github.com/samtools/samtools/releases/download/1.17/samtools-1.17.tar.bz2 \
    && tar -xjf samtools-1.17.tar.bz2 \
    && cd samtools-1.17 \
    && make \
    && make install \
    && rm -rf /tmp/*

WORKDIR /data

