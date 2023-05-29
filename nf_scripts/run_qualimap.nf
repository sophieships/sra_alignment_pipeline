process run_qualimap {
    cpus params.cpus
    container 'eoksen/qualimab:v2.2.1'

    publishDir 'results/qualimap', mode: 'copy'

    input:
    path(sorted_bam)

    output:
    path("${sorted_bam.baseName}"), emit: qualimap_results

    script:
    """
    qualimap bamqc -outdir ${sorted_bam.baseName} -bam ${sorted_bam} -nt ${task.cpus}
    """
}