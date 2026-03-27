#!/bin/bash

# Create and use a new builder instance
docker buildx create --use

# Associative array mapping directory names to Docker Hub image tags
declare -A image_tags=(
    [aria2]="eoksen/aria2-sra-download:1.35"
    [bcftools]="eoksen/bcftools:1.17"
    [biopython]="eoksen/biopython-pysam:3.9"
    [fastp]="eoksen/fastp:v0.23.3"
    [pigz]="eoksen/pigz:2.6-1"
    [qualimap]="eoksen/qualimab:v2.2.1"
    [samtools]="eoksen/samtools:1.17"
    [sra-parser]="eoksen/sra-parser:1.0"
)

# Loop over the packages and build each Docker image
for pkg in "${!image_tags[@]}"; do
    docker buildx build --platform linux/amd64,linux/arm64 -t "${image_tags[$pkg]}" -f "./dockerfiles/multiarch/$pkg/Dockerfile" .
done

# Build the bowtie2 Docker image based on user's architecture
arch=$1
if [ "$arch" = "arm" ]; then
    docker buildx build --platform linux/arm64 -t "eoksen/bowtie2.5.1:arm64" -f "./dockerfiles/arm/bowtie2.51/Dockerfile" .
elif [ "$arch" = "x86" ]; then
    docker buildx build --platform linux/amd64 -t "eoksen/bowtie2.5.1:x86_64" -f "./dockerfiles/x86/bowtie2.51/Dockerfile" .
elif [ "$arch" = "multiarch" ]; then
    docker buildx build --platform linux/arm64 -t "eoksen/bowtie2.5.1:arm64" -f "./dockerfiles/arm/bowtie2.51/Dockerfile" .
    docker buildx build --platform linux/amd64 -t "eoksen/bowtie2.5.1:x86_64" -f "./dockerfiles/x86/bowtie2.51/Dockerfile" .
else
    echo "Invalid architecture. Please enter 'arm', 'x86', or 'multiarch'."
fi
