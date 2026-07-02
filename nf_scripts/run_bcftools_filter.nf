process run_bcftools_filter {
    label 'process_medium'

    container "${params.container_image}"

    publishDir "${params.outdir}/${vcf_file.simpleName}/filtered_vcfs", mode: 'copy'

    input:
    path(vcf_file)

    output:
    path("*_filtered.vcf.gz"), emit: filtered_vcf_files
    path("filtered_stats_files/*"), emit: filtered_stats_files
    path("filtered_stats_plots/*"), emit: filtered_stats_plots

    script:
    """
    # Filter the variants based on user provided exclusion criteria and then generate stats and plots for the filtered vcfs
    if [[ '${params.exclude}' != '' ]]; then
        bcftools filter -e '${params.exclude}' --threads ${task.cpus} -o excluded_filtered.vcf.gz ${vcf_file}
        
        mkdir -p filtered_stats_files/excluded
        bcftools stats excluded_filtered.vcf.gz > filtered_stats_files/excluded/excluded.vcf.gz.stats
        mkdir -p filtered_stats_plots/excluded
        # Best-effort: the stock bcftools biocontainer has no matplotlib for plot-vcfstats.
        plot-vcfstats -p filtered_stats_plots/excluded/ filtered_stats_files/excluded/excluded.vcf.gz.stats \\
            || echo "plot-vcfstats skipped: no matplotlib in the runtime image" >&2
    fi
    # Filter the variants based on user provided inclusion criteria and then generate stats and plots for the filtered vcfs
    if [[ '${params.include}' != '' ]]; then
        bcftools filter -i '${params.include}' --threads ${task.cpus} -o included_filtered.vcf.gz ${vcf_file}
        
        mkdir -p filtered_stats_files/included
        bcftools stats included_filtered.vcf.gz > filtered_stats_files/included/included.vcf.gz.stats
        mkdir -p filtered_stats_plots/included
        # Best-effort: the stock bcftools biocontainer has no matplotlib for plot-vcfstats.
        plot-vcfstats -p filtered_stats_plots/included/ filtered_stats_files/included/included.vcf.gz.stats \\
            || echo "plot-vcfstats skipped: no matplotlib in the runtime image" >&2
    fi
    """

    stub:
    """
    touch stub_filtered.vcf.gz
    mkdir -p filtered_stats_files filtered_stats_plots
    touch filtered_stats_files/stub.vcf.gz.stats
    touch filtered_stats_plots/stub.png
    """
}
