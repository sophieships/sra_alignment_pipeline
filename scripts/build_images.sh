#!/bin/bash

# Create and use a new builder instance
docker buildx create --use

# Array of package names
packages=(aria2 bcftools biopython fastp pigz qualimab samtools sra-parser)

# Loop over the packages and build each Docker image
for pkg in "${packages[@]}"; do
    docker buildx build --platform linux/amd64,linux/arm64 -t "$pkg" -f "./dockerfiles/multiarch/$pkg/Dockerfile" .
done

# Build the bowtie2 Docker image based on user's architecture
arch=$1
if [ "$arch" = "arm" ]; then
    docker buildx build --platform linux/arm64 -t "bowtie2.51:arm" -f "./dockerfiles/arm/bowtie2.51/Dockerfile" .
elif [ "$arch" = "x86" ]; then
    docker buildx build --platform linux/amd64 -t "bowtie2.51:x86" -f "./dockerfiles/x86/bowtie2.51/Dockerfile" .
elif [ "$arch" = "multiarch" ]; then
    docker buildx build --platform linux/arm64 -t "bowtie2.51:arm" -f "./dockerfiles/arm/bowtie2.51/Dockerfile" .
    docker buildx build --platform linux/amd64 -t "bowtie2.51:x86" -f "./dockerfiles/x86/bowtie2.51/Dockerfile" .
else
    echo "Invalid architecture. Please enter 'arm', 'x86', or 'multiarch'."
fi
