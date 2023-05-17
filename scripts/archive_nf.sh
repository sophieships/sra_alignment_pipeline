#!/bin/bash

# Define the base directory where you want to move the work and log files
archive_base_dir="nextflow_archive"

# Create the base directory if it doesn't exist
mkdir -p $archive_base_dir

# Create a unique subdirectory for this run using a timestamp
run_dir="${archive_base_dir}/run_$(date +%Y%m%d_%H%M%S)"

# Create the unique subdirectory
mkdir -p $run_dir

# Move the work directory, the .nextflow.log file, and other .nextflow* files to the run directory
mv work $run_dir/
mv .nextflow.log $run_dir/
mv .nextflow* $run_dir/
