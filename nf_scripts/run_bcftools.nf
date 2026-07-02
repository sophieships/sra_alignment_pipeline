process run_bcftools {
    label 'process_medium'
    container "${params.container_image}"

    publishDir "${params.outdir}/${sorted_bam.simpleName}/bcftools", mode: 'copy'

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

    # Calculate statistics and generate svg plots.
    # plot-vcfstats renders its graphs with python3 + matplotlib, which the stock
    # bcftools biocontainer does not ship (bioconda's bcftools has no python).
    # Treat plotting as best-effort so the pipeline stays green on stock
    # biocontainers: the VCF stats themselves are still produced here and are
    # aggregated by MultiQC. A from-source bcftools image with matplotlib (see
    # dockerfiles/multiarch/bcftools) renders the full plot set.
    bcftools stats ${sorted_bam.simpleName}_calls.vcf.gz > ${sorted_bam.simpleName}_calls.vcf.gz.stats
    plot-vcfstats -v -p ${sorted_bam.simpleName}_stats_plots ${sorted_bam.simpleName}_calls.vcf.gz.stats \\
        || echo "plot-vcfstats skipped: no matplotlib in the runtime image" >&2
    mkdir -p ${sorted_bam.simpleName}_stats_plots
    """

    stub:
    """
    touch ${sorted_bam.simpleName}_calls.vcf.gz
    touch ${sorted_bam.simpleName}_consensus.fasta
    touch ${sorted_bam.simpleName}_calls.vcf.gz.stats
    mkdir -p ${sorted_bam.simpleName}_stats_plots
    touch ${sorted_bam.simpleName}_stats_plots/summary.txt
    """
}
