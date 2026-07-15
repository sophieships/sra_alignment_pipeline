process run_fasterq_dump {
    label 'process_medium'
    container "${params.container_image}"

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
    fasterq-dump ${download_status.SimpleName} --split-files --skip-technical --threads ${task.cpus} -b 100M -c 200M -m 4G

    if [ ! -s ${download_status.SimpleName}_1.fastq ] || [ ! -s ${download_status.SimpleName}_2.fastq ]; then
        rm -f ${download_status.SimpleName}_1.fastq ${download_status.SimpleName}_2.fastq
        echo 'SRA Toolkit fallback did not produce a complete paired-end read set for ${download_status.SimpleName}; single-end input is not supported.' >&2
        exit 1
    fi
    """

    stub:
    """
    touch ${download_status.SimpleName}_1.fastq ${download_status.SimpleName}_2.fastq
    """
}
