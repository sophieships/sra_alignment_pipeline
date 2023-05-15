#!/usr/bin/env nextflow

// Validate parameters
if (params.sra_accession == '') {
    error "You must provide an SRA accession number with --sra_accession"
}

accessions = params.sra_accession.split(',')
accessions_channel = Channel.from(accessions)

process fasterq_dump {
    container 'ncbi/sra-tools:aarch64-3.0.1'

    // Specify "/bin/sh" for this container
    shell '/bin/sh'

    input:
    val(sra_accession) from accessions_channel

    output:
    set val(sra_accession), file("${sra_accession}*.fastq") into reads

    """
    fasterq-dump ${sra_accession}
    """
}

process fastqc {
    tag "$name"
    container 'fastqc_trimmomatic:latest'
    
    input:
    set val(name), file(reads) from reads

    output:
    file "*_fastqc.{zip,html}" into fastqc_results

    script:
    """
    fastqc -q $reads
    """
}

process trimmomatic {
    tag "$name"
    container 'fastqc_trimmomatic:latest'
    
    input:
    set val(name), file(reads) from reads
    
    output:
    set val(name), file("*_{1,2}.fastq.gz") into trimmed_reads

    script:
    """
    java -jar /usr/local/bin/trimmomatic-0.39.jar PE -threads $task.cpus $reads[0] $reads[1] ${name}_1.fastq.gz ${name}_1_unpaired.fastq.gz ${name}_2.fastq.gz ${name}_2_unpaired.fastq.gz ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
    """
}