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

    publishDir 'results/fastq_dump', mode: 'copy'

    input:
    val(sra_accession) from accessions_channel

    output:
    set val(sra_accession), file("${sra_accession}_*.fastq.gz") into reads_into_fastp

    script:
    """
    fastq-dump --split-3 --skip-technical --gzip ${sra_accession}
    """
}

process run_fastp {
    container 'eoksen/fastp:latest'

    publishDir 'results/fastp', mode: 'copy'

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
    container 'eoksen/biopython-pysam:latest'

    publishDir 'results/downloaded_fasta', mode: 'copy'

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

    publishDir 'results/bowtie2', mode: 'copy'

    input:
    set val(name), file(reads) from trimmed_reads
    file reference from downloadedFasta

    output:
    file("${name}.sam") into sam_files
    file("${name}_pair.align") into aligned_reads
    file("${name}_pair.unmapped") into unmapped_reads

    script:
    """
    bowtie2-build -f ${reference} ref_index -p ${task.cpus}
    bowtie2 -p ${task.cpus} -x ref_index -1 ${reads[0]} -2 ${reads[1]} -S ${name}.sam --al ${name}_pair.align --un ${name}_pair.unmapped -L ${params.L} -X ${params.X} --fr -q -t
    """
}

process run_samtools {
    cpus params.cpus
    container 'eoksen/samtools-arm:latest'

    publishDir 'results/samtools', mode: 'copy'

    input:
    file(sam_file) from sam_files
    file(reference) from downloadedFasta

    output:
    file("${sam_file.baseName}.sorted.bam").into(sorted_bam_files_for_bcftools, sorted_bam_files_for_qualimap)
    file("${sam_file.baseName}.sorted.bam.bai") into bam_index_files
    tuple(file("${reference}"), file("${reference}.fai")) into indexed_references


    script:
    """
    samtools view -b ${sam_file} -o ${sam_file.baseName}.bam
    samtools sort -@ ${task.cpus} -o ${sam_file.baseName}.sorted.bam ${sam_file.baseName}.bam
    samtools index ${sam_file.baseName}.sorted.bam
    samtools faidx ${reference}
    """
}


process run_bcftools {
    cpus params.cpus
    container 'eoksen/bcftools-1.17-arm:latest'

    publishDir 'results/bcftools', mode: 'copy'

    input:
    file(sorted_bam) from sorted_bam_files_for_bcftools
    tuple(file(reference_fasta_gz), file(reference_fai)) from indexed_references

    output:
    file("calls.vcf.gz") into vcf_files
    file("consensus.fasta") into consensus_sequences

    script:
    """
    # Call variants
    bcftools mpileup -Ou -f ${reference_fasta_gz} --threads ${task.cpus} ${sorted_bam} | bcftools call -mv -Oz -o calls.vcf.gz

    # Index the variant file
    bcftools index calls.vcf.gz

    # Generate the consensus sequence
    zcat ${reference_fasta_gz} | bcftools consensus calls.vcf.gz > consensus.fasta
    """
}

process run_qualimap {
    container 'eoksen/qualimab-v2.2.1:latest'

    publishDir 'results/qualimap', mode: 'copy'

    input:
    file(bam_file) from sorted_bam_files_for_qualimap

    output:
    file("bamqc_ref") into qualimap_results

    script:
    """
    qualimap bamqc -outdir bamqc_ref -bam ${bam_file}
    """
}
