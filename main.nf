// Validate parameters
if (params.sra_accession == '' && params.identifier == '' && params.input_file == '') {
    error "You must provide either an SRA accession number and identifier with --sra_accession and --identifier, or an input file with --input_file"
}

if ((params.sra_accession == '' || params.identifier == '') && params.input_file == '') {
    error("You have only provided one of the SRA accession or identifier. Both or an input file must be provided. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64> \nOr provide an input file: nextflow run main.nf --input_file <file> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.input_file != '' && (params.sra_accession != '' || params.identifier != '')) {
    log.warn("Both an input file and individual SRA accession and/or identifier are provided. Only the input file will be used for the pipeline.")
}

if (params.email == '') {
    error("No email provided. Specify it with --email. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.cpus == '' || !params.cpus.toString().isNumber()) {
    error("Invalid or no CPU number provided. Specify it with --cpus. It should be a number. \nTo check the number of CPUs on your system: \n- Unix-based (Linux/MacOS/WSL2): use the 'nproc' command \nnextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.architecture == '') {
    error("No architecture provided. Specify it with --architecture. \nTo check your system's architecture: \n- Unix-based (Linux/MacOS/WSL2): use the 'uname -m' command \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

include { get_srrs } from './nf_scripts/get_srrs'
include { parse_srrs } from './nf_scripts/parse_srrs'
include { download_fastq } from './nf_scripts/download_fastq'
include { fastq_dump } from './nf_scripts/fastq_dump'
include { compress_reads } from './nf_scripts/compress_reads.nf'
include { run_fastp } from './nf_scripts/run_fastp'
include { downloadfasta } from './nf_scripts/downloadfasta'
include { run_bowtie2 } from './nf_scripts/run_bowtie2'
include { run_samtools } from './nf_scripts/run_samtools'
include { run_bcftools } from './nf_scripts/run_bcftools'
include { run_qualimap } from './nf_scripts/run_qualimap'
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter'

if (params.sra_accession && params.identifier && params.input_file == '') {
    log.info("SRA accession and identifier provided. Downloading SRRs from SRA.")
    Channel.value([params.sra_accession, params.identifier])
        .set { accessions_channel }
} 

workflow {
    if (params.input_file == '') {
        log.info("No input file provided. Downloading SRRs from SRA.")
        accessions = accessions_channel.map { it[0] }
        identifiers = accessions_channel.map { it[1] }
        get_srrs( accessions, identifiers )
            srr_tuples = get_srrs.out.srr_list
                     .collectFile()
                     .splitCsv(header: false)
                     .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }
        download_fastq( sra_accessions_channel, params.email )
        fastq_dump( sra_accessions_channel, download_fastq.out.download_status )
        compress_reads( fastq_dump.out.forward_reads.join(fastq_dump.out.reverse_reads), download_fastq.out.download_status )
        forward_reads = download_fastq.out.gzip_forward_reads.mix(compress_reads.out.gzip_forward_reads)
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix(compress_reads.out.gzip_reverse_reads)
    }
    else {
        log.info("Input file provided. Parsing SRRs from input file.")
        input_file_channel = Channel.fromPath(params.input_file)
        parse_srrs( input_file_channel )

        srr_tuples = parse_srrs.out.parsed_srrs
                    .collectFile()
                    .splitCsv(header: false)
                    .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }
        download_fastq( sra_accessions_channel, params.email )
        fastq_dump( sra_accessions_channel, download_fastq.out.download_status )
        compress_reads( fastq_dump.out.forward_reads.join(fastq_dump.out.reverse_reads), download_fastq.out.download_status )
        forward_reads = download_fastq.out.gzip_forward_reads.mix(compress_reads.out.gzip_forward_reads)
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix(compress_reads.out.gzip_reverse_reads)
    }
    run_fastp( forward_reads.join(reverse_reads) )
    downloadfasta( identifiers_channel, params.email )
    run_bowtie2( run_fastp.out.trimmed_forward_reads.join(run_fastp.out.trimmed_reverse_reads), downloadfasta.out.downloaded_fasta )
    run_samtools( run_bowtie2.out.bowtie2_output, downloadfasta.out.downloaded_fasta )
    run_bcftools( run_samtools.out.sorted_bam, run_samtools.out.indexed_references )
    run_qualimap( run_samtools.out.sorted_bam )

    if (params.include || params.exclude) {
        run_bcftools_filter( run_bcftools.out.vcf_files )
    }
}