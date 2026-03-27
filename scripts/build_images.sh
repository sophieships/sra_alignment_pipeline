#!/bin/bash
set -e

# Create or reuse a named builder instance (avoids accumulating anonymous builders)
BUILDER_NAME="sra-pipeline-builder"
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    docker buildx create --name "$BUILDER_NAME"
fi
docker buildx use "$BUILDER_NAME"

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
# Build context is the Dockerfile's directory so COPY commands resolve correctly
for pkg in "${!image_tags[@]}"; do
    echo "=== Building ${image_tags[$pkg]} ==="
    docker buildx build --platform linux/amd64,linux/arm64 -t "${image_tags[$pkg]}" --push -f "./dockerfiles/multiarch/$pkg/Dockerfile" "./dockerfiles/multiarch/$pkg"
done

# Build the bowtie2 Docker image based on user's architecture
arch=$1
if [ "$arch" = "arm" ]; then
    echo "=== Building eoksen/bowtie2.5.1:arm64 ==="
    docker buildx build --platform linux/arm64 -t "eoksen/bowtie2.5.1:arm64" --push -f "./dockerfiles/arm/bowtie2.51/Dockerfile" "./dockerfiles/arm/bowtie2.51"
elif [ "$arch" = "x86" ]; then
    echo "=== Building eoksen/bowtie2.5.1:x86_64 ==="
    docker buildx build --platform linux/amd64 -t "eoksen/bowtie2.5.1:x86_64" --push -f "./dockerfiles/x86/bowtie2.51/Dockerfile" "./dockerfiles/x86/bowtie2.51"
elif [ "$arch" = "multiarch" ]; then
    echo "=== Building eoksen/bowtie2.5.1:arm64 ==="
    docker buildx build --platform linux/arm64 -t "eoksen/bowtie2.5.1:arm64" --push -f "./dockerfiles/arm/bowtie2.51/Dockerfile" "./dockerfiles/arm/bowtie2.51"
    echo "=== Building eoksen/bowtie2.5.1:x86_64 ==="
    docker buildx build --platform linux/amd64 -t "eoksen/bowtie2.5.1:x86_64" --push -f "./dockerfiles/x86/bowtie2.51/Dockerfile" "./dockerfiles/x86/bowtie2.51"
else
    echo "Invalid architecture. Please enter 'arm', 'x86', or 'multiarch'."
fi
