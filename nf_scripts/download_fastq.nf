process download_fastq {
    label 'process_low'
    maxForks 1
    container "${params.container_image}"
    errorStrategy 'ignore'

    publishDir "${params.outdir}/${sra_accession}/fastq", mode: 'copy'

    input:
    val sra_accession

    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq.gz"), optional: true, emit: gzip_forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq.gz"), optional: true, emit: gzip_reverse_reads
    path("${sra_accession}.txt"), optional: true, emit: download_status


    script:
    """
    /scripts/sra_download.sh ${sra_accession}
    """

    // Read-path choice (see PR): emit ONLY the gz reads and DO NOT create
    // ${sra_accession}.txt. In the real pipeline ${sra_accession}.txt is written
    // ONLY when the ENA FTP download FAILS; its presence triggers the
    // fasterq-dump -> pigz fallback (run_fasterq_dump `when: download_status.exists()`).
    // We reproduce the ENA-SUCCESS branch, giving a SINGLE clean read source
    // (download_fastq's gz reads; run_fasterq_dump/run_pigz stay dormant). This
    // avoids feeding duplicate sample keys into main.nf's .mix() (join cardinality
    // bugs) AND avoids the fasterq-dump fallback, whose sra-tools image lacks
    // /bin/bash and cannot run under Nextflow's docker wrapper (pre-existing latent
    // bug; see follow-up note in the PR).
    stub:
    """
    touch ${sra_accession}_1.fastq.gz ${sra_accession}_2.fastq.gz
    """
}
