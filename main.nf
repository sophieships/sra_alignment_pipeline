#!/usr/bin/env nextflow

// Validate parameters
if (params.sra_accession == '') {
    error "You must provide an SRA accession number with --sra_accession"
}

accessions = params.sra_accession.split(',')
accessions_channel = Channel.from(accessions)

process fastq_dump {
    container 'ncbi/sra-tools:aarch64-3.0.1'

    // Specify "/bin/sh" for this container
    shell '/bin/sh'

    input:
    val(sra_accession) from accessions_channel

    output:
    set val(sra_accession), file("${sra_accession}_*.fastq.gz") into reads_into_fastp

    """
    fastq-dump --split-3 --skip-technical --gzip ${sra_accession}
    """
}

process run_fastp {
    container 'eoksen/fastp:latest'

    input:
    set val(name), file(reads) from reads_into_fastp

    output:
    set val(name), file("*_trimmed*.fastq.gz") into trimmed_reads

    script:
    """
    if [[ ${reads.size()} -gt 1 ]]; then
        fastp -i ${reads[0]} -I ${reads[1]} -o ${name}_trimmed_1.fastq.gz -O ${name}_trimmed_2.fastq.gz
    else
        fastp -i ${reads[0]} -o ${name}_trimmed.fastq.gz
    fi
    """
}