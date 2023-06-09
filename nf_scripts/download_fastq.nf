process download_fastq {
    maxForks 1
    container 'eoksen/aria2-sra-download:1.35'
    errorStrategy 'ignore'

    publishDir 'results/fastq', mode: 'copy'

    input:
    val sra_accession
    val emailval

    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq.gz"), optional: true, emit: gzip_forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq.gz"), optional: true, emit: gzip_reverse_reads
    path("${sra_accession}.txt"), optional: true, emit: download_status


    script:
    """
    /scripts/sra_download.sh ${sra_accession} ${emailval}
    """
}
