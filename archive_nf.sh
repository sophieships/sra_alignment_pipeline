#!/bin/bash

# Define the directory where you want to move the work and log files
archive_dir="nextflow_archive"

# Create the directory if it doesn't exist
mkdir -p $archive_dir

# Move the work directory and the .nextflow.log file to the archive directory
mv work $archive_dir/
mv .nextflow.log* $archive_dir/
mv .nextflow $archive_dir/

