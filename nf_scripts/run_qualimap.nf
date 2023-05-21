process run_qualimap {
    container 'eoksen/qualimab:v2.2.1'

    publishDir 'results/qualimap', mode: 'copy'

    input:
    path(sorted_bam)

    output:
    path("bamqc_ref"), emit: qualimap_results

    script:
    """
    qualimap bamqc -outdir bamqc_ref -bam ${sorted_bam}
    """
}