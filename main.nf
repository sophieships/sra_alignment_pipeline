#!/usr/bin/env nextflow

// Validate parameters
if (params.sra_accession == '') {
    error "You must provide an SRA accession number with --sra_accession"
}

accessions = params.sra_accession.split(',')
accessions_channel = Channel.from(accessions)

process fastq_dump {
    container 'ncbi/sra-tools:3.0.1'

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
    val emailval from params.email

    output:
    file("${identifierVal}_reference.fasta.gz") into downloadedFasta

    script:
    """
    python /scripts/download_fasta.py ${identifierVal} ${emailval}

    """
}

process run_bowtie2 {
    cpus params.cpus
    container 'eoksen/bowtie2.5.1:${params.architecture}'

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
    container 'eoksen/bcftools:1.17'

    publishDir 'results/bcftools', mode: 'copy'

    input:
    file(sorted_bam) from sorted_bam_files_for_bcftools
    tuple(file(reference_fasta_gz), file(reference_fai)) from indexed_references

    output:
    file("calls.vcf.gz") into vcf_files
    file("consensus.fasta") into consensus_sequences
    file("calls.vcf.gz.stats") into stats_files
    file("stats_plots/") into stats_plots

    script:
    """
    # Call variants
    bcftools mpileup -Ou -f ${reference_fasta_gz} --threads ${task.cpus} ${sorted_bam} | bcftools call --ploidy ${params.ploidy} -mv -Oz -o calls.vcf.gz

    # Index the variant file
    bcftools index calls.vcf.gz

    # Generate the consensus sequence
    zcat ${reference_fasta_gz} | bcftools consensus calls.vcf.gz > consensus.fasta

    # Calculate statistics and generate plots
    bcftools stats calls.vcf.gz > calls.vcf.gz.stats
    mkdir stats_plots
    plot-vcfstats -p stats_plots/ calls.vcf.gz.stats
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

process run_bcftools_filter {
    cpus params.cpus

    container 'eoksen/bcftools:1.17'

    publishDir 'results/filtered_vcfs', mode: 'copy'

    input:
    file(vcf_file) from vcf_files

    output:
    file("*_filtered.vcf.gz") into filtered_vcf_files
    file("filtered_stats_files/*") into filtered_stats_files
    file("filtered_stats_plots/*") into filtered_stats_plots

    when:
    params.include || params.exclude

    script:
    """
    # Filter the variants based on user provided exclusion criteria and then generate stats and plots for the filtered vcfs
    if [[ '${params.exclude}' != '' ]]; then
        bcftools filter -e '${params.exclude}' --threads ${task.cpus} -o excluded_filtered.vcf.gz ${vcf_file}
        
        mkdir -p filtered_stats_files/excluded
        bcftools stats excluded_filtered.vcf.gz > filtered_stats_files/excluded/excluded.vcf.gz.stats
        mkdir -p filtered_stats_plots/excluded
        plot-vcfstats -p filtered_stats_plots/excluded/ filtered_stats_files/excluded/excluded.vcf.gz.stats
    fi
    # Filter the variants based on user provided inclusion criteria and then generate stats and plots for the filtered vcfs
    if [[ '${params.include}' != '' ]]; then
        bcftools filter -i '${params.include}' --threads ${task.cpus} -o included_filtered.vcf.gz ${vcf_file}
        
        mkdir -p filtered_stats_files/included
        bcftools stats included_filtered.vcf.gz > filtered_stats_files/included/included.vcf.gz.stats
        mkdir -p filtered_stats_plots/included
        plot-vcfstats -p filtered_stats_plots/included/ filtered_stats_files/included/included.vcf.gz.stats
    fi
    """
}
