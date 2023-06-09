process run_qualimap {
    cpus params.cpus
    container 'eoksen/qualimab:v2.2.1'

    publishDir "results/${sorted_bam.simpleName}/qualimap", mode: 'copy'

    input:
    path(sorted_bam)

    output:
    path("${sorted_bam.simpleName}"), emit: qualimap_results

    script:
    """
    qualimap bamqc -outdir ${sorted_bam.simpleName} -bam ${sorted_bam} -nt ${task.cpus}
    """
}