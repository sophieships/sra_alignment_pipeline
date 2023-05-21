process run_bcftools_filter {
    cpus params.cpus

    container 'eoksen/bcftools:1.17'

    publishDir 'results/filtered_vcfs', mode: 'copy'

    input:
    path(vcf_file)

    output:
    path("*_filtered.vcf.gz"), emit: filtered_vcf_files
    path("filtered_stats_files/*"), emit: filtered_stats_files
    path("filtered_stats_plots/*"), emit: filtered_stats_plots

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
