process run_multiqc {
    label 'process_low'
    // Pinned biocontainer. MultiQC resolves its own image here rather than through
    // conf/images.json (whose images are also biocontainers); it could be folded
    // into the manifest later. Tag confirmed pullable via `docker manifest inspect`.
    container 'quay.io/biocontainers/multiqc:1.25--pyhdfd78af_0'

    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    path(qc_files)

    output:
    path("multiqc_report.html"), emit: report
    path("multiqc_data"), emit: data

    script:
    """
    multiqc . --force
    """

    stub:
    """
    touch multiqc_report.html
    mkdir -p multiqc_data
    touch multiqc_data/multiqc_sources.txt
    """
}
