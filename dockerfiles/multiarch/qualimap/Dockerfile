# Using Debian as base image
FROM debian:buster

# Set environment variables
ENV QUALIMAP_VERSION="2.2.1" \
    R_VERSION="3.6.3"

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    openjdk-11-jdk \
    build-essential \
    libcurl4-gnutls-dev \
    libxml2-dev \
    libssl-dev \
    default-libmysqlclient-dev \
    libcairo2-dev \
    libxt-dev \
    x11-common \
    libx11-6 \
    libx11-dev \
    libpng-dev \
    libreadline-dev \
    gfortran \
    unzip \
    libbz2-dev \
    liblzma-dev  # Add this line

# Install R
RUN curl -O https://cran.r-project.org/src/base/R-3/R-${R_VERSION}.tar.gz && \
    tar -xf R-${R_VERSION}.tar.gz && \
    cd R-${R_VERSION} && \
    ./configure --with-x=no && \
    make && \
    make install && \
    cd .. && \
    rm -rf R-${R_VERSION} R-${R_VERSION}.tar.gz

# Install qualimap
RUN curl -LO https://bitbucket.org/kokonech/qualimap/downloads/qualimap_v${QUALIMAP_VERSION}.zip && \
    unzip qualimap_v${QUALIMAP_VERSION}.zip && \
    rm qualimap_v${QUALIMAP_VERSION}.zip && \
    mv qualimap_v${QUALIMAP_VERSION} /opt/qualimap

# Set PATH
ENV PATH="/opt/qualimap:${PATH}"
