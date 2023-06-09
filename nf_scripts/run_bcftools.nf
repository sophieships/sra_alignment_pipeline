process run_bcftools {
    cpus params.cpus
    container 'eoksen/bcftools:1.17'

    publishDir "results/${sorted_bam.simpleName}/bcftools", mode: 'copy'

    input:
    path(sorted_bam)
    tuple(path(reference_fasta_gz), path(reference_fai))

    output:
    path("${sorted_bam.simpleName}_calls.vcf.gz"), emit: vcf_files
    path("${sorted_bam.simpleName}_consensus.fasta"), emit: consensus_sequences
    path("${sorted_bam.simpleName}_calls.vcf.gz.stats"), emit: stats_files
    path("${sorted_bam.simpleName}_stats_plots"), emit: stats_plots

    script:
    """
    # Call variants
    bcftools mpileup -Ou -f ${reference_fasta_gz} --threads ${task.cpus} ${sorted_bam} | bcftools call --ploidy ${params.ploidy} -mv -Oz -o ${sorted_bam.simpleName}_calls.vcf.gz

    # Index the variant file
    bcftools index ${sorted_bam.simpleName}_calls.vcf.gz

    # Generate the consensus sequence
    zcat ${reference_fasta_gz} | bcftools consensus ${sorted_bam.simpleName}_calls.vcf.gz > ${sorted_bam.simpleName}_consensus.fasta

    # Calculate statistics and generate svg plots
    bcftools stats ${sorted_bam.simpleName}_calls.vcf.gz > ${sorted_bam.simpleName}_calls.vcf.gz.stats
    plot-vcfstats -v -p ${sorted_bam.simpleName}_stats_plots ${sorted_bam.simpleName}_calls.vcf.gz.stats
    """
}