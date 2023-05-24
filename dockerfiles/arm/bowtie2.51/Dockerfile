FROM ubuntu:20.04

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl unzip python3 perl && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Fetch and unzip Bowtie2
RUN curl -LO https://github.com/BenLangmead/bowtie2/releases/download/v2.5.1/bowtie2-2.5.1-linux-aarch64.zip && \
    unzip bowtie2-2.5.1-linux-aarch64.zip && \
    rm bowtie2-2.5.1-linux-aarch64.zip

# Add Bowtie2 to PATH
ENV PATH="/app/bowtie2-2.5.1-linux-aarch64:${PATH}"


