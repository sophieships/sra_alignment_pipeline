FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    zlib1g-dev \
    libncurses5-dev \
    libbz2-dev \
    liblzma-dev \
    libcurl4-gnutls-dev \
    perl \
    python3 \
    python3-pip \
    m4 \
    make \
    bash \
    texlive-latex-base \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-latex-extra \
    && rm -rf /var/lib/apt/lists/*

# Set timezone
RUN ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && dpkg-reconfigure --frontend noninteractive tzdata

# Unset DEBIAN_FRONTEND
RUN unset DEBIAN_FRONTEND

WORKDIR /tmp

RUN wget https://github.com/samtools/bcftools/releases/download/1.17/bcftools-1.17.tar.bz2 \
    && tar -xjf bcftools-1.17.tar.bz2 \
    && cd bcftools-1.17 \
    && make \
    && make install \
    && pip3 install matplotlib \
    && rm -rf /tmp/*

WORKDIR /data
