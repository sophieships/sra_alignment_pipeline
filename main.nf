// If no SRA accession number, identifier, or input file is provided, throw an error.
if ( params.sra_accession == '' && params.identifier == '' && params.input_file == '' ) {
    error "You must provide either an SRA accession number and identifier with --sra_accession and --identifier, or an input file with --input_file"
}

// If only one of the SRA accession or identifier is provided without an input file, throw an error.
if (( params.sra_accession == '' || params.identifier == '' ) && params.input_file == '' ) {
    error("You have only provided one of the SRA accession or identifier. Both or an input file must be provided. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64> \nOr provide an input file: nextflow run main.nf --input_file <file> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

// If both an input file and individual SRA accession and/or identifier are provided, log a warning that only the input file will be used.
if ( params.input_file != '' && ( params.sra_accession != '' || params.identifier != '' )) {
    log.warn("Both an input file and individual SRA accession and/or identifier are provided. Only the input file will be used for the pipeline.")
}

// If no email is provided, throw an error. 
if ( params.email == '' ) {
    error("No email provided. Specify it with --email. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

// If the provided CPU number is not a number, throw an error.
if ( !params.cpus.toString().isNumber() ) {
    error("Invalid CPU number provided. Specify it with --cpus <int>. It should be an integer. \nTo check the number of CPUs on your system: \n- Unix-based (Linux/MacOS/WSL2): use the 'nproc' command \n- To adjust system cpu and memory allocation for Docker, go to Docker Desktop, then settings/resources and set cpu and memory parameters. \nnextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

// If the provided architecture is neither 'arm64' nor 'x86_64', throw an error.
if ( params.architecture != 'arm64' && params.architecture != 'x86_64' ) {
    error("You must specify --architecture 'arm64' or 'x86_64' to run the bowtie2 docker container. \nTo check your system's architecture: \n- Unix-based (Linux/MacOS/WSL2): use the 'uname -m' command \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

include { get_srrs } from './nf_scripts/get_srrs'
include { parse_srrs } from './nf_scripts/parse_srrs'
include { download_fastq } from './nf_scripts/download_fastq'
include { run_fasterq_dump } from './nf_scripts/run_fasterq_dump'
include { run_pigz } from './nf_scripts/run_pigz'
include { run_fastp } from './nf_scripts/run_fastp'
include { download_fasta } from './nf_scripts/download_fasta'
include { run_bowtie2 } from './nf_scripts/run_bowtie2'
include { run_samtools } from './nf_scripts/run_samtools'
include { run_bcftools } from './nf_scripts/run_bcftools'
include { run_qualimap } from './nf_scripts/run_qualimap'
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter'

workflow {
    if ( params.sra_accession && params.identifier && params.input_file == '' ) {
        log.info("SRA accession and identifier provided. Downloading SRRs from SRA.")
        Channel.value( [params.sra_accession, params.identifier] )
            .set { accessions_channel }

        accessions = accessions_channel.map { it[0] }
        identifiers = accessions_channel.map { it[1] }
        get_srrs( accessions, identifiers )
            srr_tuples = get_srrs.out.srr_list
                     .collectFile()
                     .splitCsv( header: false )
                     .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }

        download_fastq( sra_accessions_channel, params.email )
        
        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join( run_fasterq_dump.out.reverse_reads), download_fastq.out.download_status )

        // mix the forward and reverse reads from download_fastq and run_pigz
        forward_reads = download_fastq.out.gzip_forward_reads.mix( run_pigz.out.gzip_forward_reads )
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix( run_pigz.out.gzip_reverse_reads )

        download_fasta( sra_accessions_channel, identifiers_channel, params.email )
    }
    else {
        log.info("Input file provided. Parsing SRRs from input file.")
        Channel.fromPath( params.input_file )
            .set { input_file_channel }
        
        parse_srrs( input_file_channel )
        srr_tuples = parse_srrs.out.parsed_srrs
                    .collectFile()
                    .splitCsv( header: false) 
                    .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }

        download_fastq( sra_accessions_channel, params.email )

        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join(run_fasterq_dump.out.reverse_reads), download_fastq.out.download_status )

        // mix the forward and reverse reads from download_fastq and run_pigz
        forward_reads = download_fastq.out.gzip_forward_reads.mix( run_pigz.out.gzip_forward_reads )
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix( run_pigz.out.gzip_reverse_reads )

        download_fasta( sra_accessions_channel, identifiers_channel, params.email )

    }
    
    run_fastp( forward_reads.join( reverse_reads ) )
    
    run_bowtie2( run_fastp.out.trimmed_forward_reads.join( run_fastp.out.trimmed_reverse_reads), download_fasta.out.downloaded_fasta )
    
    run_samtools( run_bowtie2.out.bowtie2_output, download_fasta.out.downloaded_fasta )
    
    run_qualimap( run_samtools.out.sorted_bam )

    run_bcftools( run_samtools.out.sorted_bam, run_samtools.out.indexed_references )
    if ( params.include || params.exclude ) {
        run_bcftools_filter( run_bcftools.out.vcf_files )
    }
}