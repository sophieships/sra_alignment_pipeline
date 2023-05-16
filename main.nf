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
    set val(name), file("*_trimmed_{1,2}.fastq.gz") into trimmed_reads

    script:
    """
    fastp -i ${reads[0]} -I ${reads[1]} -o ${name}_trimmed_1.fastq.gz -O ${name}_trimmed_2.fastq.gz
    """
}



process downloadFasta {
    container 'eoksen/biopython:latest'

    input:
    val identifierVal from params.identifier

    output:
    file("${identifierVal}_reference.fasta.gz") into downloadedFasta

    script:
    """
    python /scripts/download_fasta.py ${identifierVal}
    """
}

process run_bowtie2 {
    cpus params.cpus
    container 'eoksen/bowtie2-arm:latest'

    input:
    set val(name), file(reads) from trimmed_reads
    file reference from downloadedFasta

    output:
    file("${name}.sam") into aligned_reads

    script:
    """
    bowtie2-build -f ${reference} ref_index -p ${task.cpus}
    bowtie2 -p ${task.cpus} -x ref_index -1 ${reads[0]} -2 ${reads[1]} -S ${name}.sam --al ${name}_pair.align --un ${name}_pair.unmapped -L 24 -X 600 --fr -q -t
    """
}
