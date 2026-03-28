FROM ubuntu:24.04

ARG LIBISAL_VERSION=v2.31.1
ARG LIBDEFLATE_VERSION=v1.25
ARG FASTP_VERSION=v1.3.0

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/lib

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libhwy-dev \
        libtool \
        nasm \
        procps \
        yasm \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --branch "${LIBISAL_VERSION}" --depth 1 https://github.com/intel/isa-l.git && \
    cd isa-l && \
    ./autogen.sh && \
    ./configure --prefix=/usr --libdir=/usr/lib && \
    make -j"$(nproc)" && \
    make install && \
    cd .. && \
    rm -rf isa-l

RUN git clone --branch "${LIBDEFLATE_VERSION}" --depth 1 https://github.com/ebiggers/libdeflate.git && \
    cd libdeflate && \
    cmake -B build && \
    cmake --build build --parallel "$(nproc)" && \
    cmake --install build && \
    cd .. && \
    rm -rf libdeflate

RUN git clone --branch "${FASTP_VERSION}" --depth 1 https://github.com/OpenGene/fastp.git && \
    cd fastp && \
    make -j"$(nproc)" && \
    make install && \
    cd .. && \
    rm -rf fastp
