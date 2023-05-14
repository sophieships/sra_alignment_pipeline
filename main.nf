#!/usr/bin/env nextflow

nextflow.enable.dsl=2
includeConfig 'conf/params.config'
includeConfig './conf/docker.config'

// Validate parameters
if (params.sra_accession == '') {
    error "You must provide an SRA accession number with --sra_accession"
}

accessions = params.sra_accession.split(',')
accessions_channel = Channel.from(accessions)

process fasterq_dump {
    container 'ncbi/sra-tools:x86_64-3.0.0'

    input:
    val(sra_accession) from accessions_channel

    output:
    file("${sra_accession}*.fastq")

    """
    fasterq-dump ${sra_accession}
    """
}

