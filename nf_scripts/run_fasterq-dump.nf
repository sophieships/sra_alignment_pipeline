process run_fasterq_dump {
    cpus params.cpus
    container 'ncbi/sra-tools:3.0.1'

    shell '/bin/sh'

    input:
    val sra_accession
    path download_status


    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq"), emit: forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq"), emit: reverse_reads

    when:
    download_status.exists()

    script:
    """
    prefetch ${sra_accession}
    fasterq-dump ${sra_accession} --threads ${task.cpus} -b 100M -c 200M -m 2G
    """
}
