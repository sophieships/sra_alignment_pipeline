process run_fasterq_dump {
    cpus params.cpus
    container 'ncbi/sra-tools:3.0.1'

    shell '/bin/sh'

    input:
    path download_status


    output:
    tuple val("${download_status.SimpleName}"), path("${download_status.SimpleName}_1.fastq"), emit: forward_reads
    tuple val("${download_status.SimpleName}"), path("${download_status.SimpleName}_2.fastq"), emit: reverse_reads

    when:
    download_status.exists()

    script:
    """
    prefetch ${download_status.SimpleName}
    fasterq-dump ${download_status.SimpleName} --threads ${task.cpus} -b 100M -c 200M -m 8G
    """
}
