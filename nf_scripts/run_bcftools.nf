process run_bcftools {
    cpus params.cpus
    container 'eoksen/bcftools:1.17'

    publishDir 'results/bcftools', mode: 'copy'

    input:
    path(sorted_bam)
    tuple(path(reference_fasta_gz), path(reference_fai))

    output:
    path("calls.vcf.gz"), emit: vcf_files
    path("consensus.fasta"), emit: consensus_sequences
    path("calls.vcf.gz.stats"), emit: stats_files
    path("stats_plots/"), emit: stats_plots

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