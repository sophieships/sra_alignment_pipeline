process download_fastq {
    label 'process_low'
    maxForks 1
    container "${params.container_image}"
    publishDir "${params.outdir}/${sra_accession}/fastq", mode: 'copy'

    input:
    val sra_accession

    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq.gz"), optional: true, emit: gzip_forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq.gz"), optional: true, emit: gzip_reverse_reads
    path("${sra_accession}.txt"), optional: true, emit: download_status


    script:
    """
    sra_download.sh ${sra_accession}
    """

    // Exercise the fallback route during pipeline stub runs. ENA-success behavior
    // is covered directly by scripts/test_download_fallback.sh.
    stub:
    """
    printf 'ENA download unavailable; use SRA Toolkit fallback for %s\n' '${sra_accession}' > ${sra_accession}.txt
    """
}
