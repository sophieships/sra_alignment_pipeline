FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/lib

WORKDIR /app

RUN apt-get update && \
    apt-get install -y git autoconf automake libtool nasm yasm cmake build-essential zlib1g-dev

RUN gcc --version > versions.txt && \
    g++ --version >> versions.txt && \
    cmake --version >> versions.txt && \
    cat versions.txt

ARG libisal_version=v2.30.0
RUN git clone https://github.com/intel/isa-l.git && \
    cd isa-l && \
    git checkout ${libisal_version} && \
    ./autogen.sh && \
    ./configure --prefix=/usr --libdir=/usr/lib && \
    make && \
    make install && \
    cd .. && \
    rm -rf isa-l

ARG libdeflate_version=v1.18
RUN git clone https://github.com/ebiggers/libdeflate.git && \
    cd libdeflate && \
    git checkout ${libdeflate_version} && \
    cmake -B build && \
    cmake --build build && \
    cmake --install build && \
    cd .. && \
    rm -rf libdeflate

ARG fastp_version=v0.23.3
RUN git clone https://github.com/OpenGene/fastp.git && \
    cd fastp && \
    git checkout ${fastp_version} && \
    make && \
    make install && \
    cd .. && \
    rm -rf fastp
