import groovy.json.JsonException
import groovy.json.JsonSlurper

// nf-schema drives declarative parameter validation and schema-generated --help
// from nextflow_schema.json. This replaces the former hand-rolled
// `if (params.x == '') error(...)` cascade. See nextflow.config for the plugin pin.
include { validateParameters; paramsHelp } from 'plugin/nf-schema'

final List REQUIRED_RUNTIME_IMAGE_KEYS = [
    'aria2',
    'bcftools',
    'biopython',
    'bowtie2',
    'fastp',
    'pigz',
    'qualimap',
    'samtools',
    'sra_parser',
    'sra_tools',
]

def resolveManifestFile(String manifestPath) {
    File manifestFile = new File(manifestPath)
    if (!manifestFile.isAbsolute()) {
        manifestFile = new File(baseDir.toString(), manifestPath)
    }
    return manifestFile
}

def manifestError(File manifestFile, String message) {
    error("Invalid container image manifest at ${manifestFile}: ${message}")
}

def loadImageManifest(String manifestPath) {
    File manifestFile = resolveManifestFile(manifestPath)
    if (!manifestFile.exists()) {
        error("Container image manifest not found: ${manifestFile}")
    }
    try {
        def parsedManifest = new JsonSlurper().parse(manifestFile)
        if (!(parsedManifest instanceof Map)) {
            manifestError(manifestFile, "top-level JSON value must be an object")
        }
        return (Map) parsedManifest
    }
    catch (JsonException exception) {
        manifestError(manifestFile, "could not parse JSON (${exception.message})")
    }
}

def normalizeParamValue(def value, String fallback) {
    String normalizedValue = value?.toString()?.trim()
    return normalizedValue ? normalizedValue : fallback
}

def requireManifestMap(Map parent, String key, File manifestFile, String pathLabel) {
    def value = parent?.get(key)
    if (!(value instanceof Map)) {
        manifestError(manifestFile, "${pathLabel} must be an object")
    }
    return (Map) value
}

def requireManifestString(Map parent, String key, File manifestFile, String pathLabel) {
    String value = parent?.get(key)?.toString()?.trim()
    if (!value) {
        manifestError(manifestFile, "${pathLabel} must be a non-empty string")
    }
    return value
}

def validateImageManifest(Map imageManifest, File manifestFile, List requiredImageKeys) {
    Map defaults = requireManifestMap(imageManifest, 'defaults', manifestFile, 'defaults')
    requireManifestString(defaults, 'registry', manifestFile, 'defaults.registry')
    requireManifestString(defaults, 'namespace', manifestFile, 'defaults.namespace')

    Map images = requireManifestMap(imageManifest, 'images', manifestFile, 'images')
    requiredImageKeys.each { String imageKey ->
        Map imageDefinition = requireManifestMap(images, imageKey, manifestFile, "images.${imageKey}")
        requireManifestString(imageDefinition, 'runtime_name', manifestFile, "images.${imageKey}.runtime_name")
        requireManifestString(imageDefinition, 'version', manifestFile, "images.${imageKey}.version")
    }
}

def buildImageReference(Map imageDefinition, String registry, String namespace) {
    String resolvedRegistry = normalizeParamValue(imageDefinition.get('registry'), registry)
    String resolvedNamespace = normalizeParamValue(imageDefinition.get('namespace'), namespace)
    String resolvedImageName = imageDefinition.runtime_name.toString()
    String resolvedVersion = imageDefinition.version.toString()
    String repository = [resolvedRegistry, resolvedNamespace, resolvedImageName]
        .findAll { it?.trim() }
        .join('/')
    return "${repository}:${resolvedVersion}"
}

def buildContainerImageMap(Map imageManifest, List requiredImageKeys, String registry, String namespace) {
    Map images = (Map) imageManifest.images
    requiredImageKeys.collectEntries { String imageKey ->
        Map imageDefinition = (Map) images[imageKey]
        [(imageKey): buildImageReference(imageDefinition, registry, namespace)]
    }
}

def imageManifestFile = resolveManifestFile(params.image_manifest.toString())
def imageManifest = loadImageManifest(params.image_manifest.toString())
validateImageManifest(imageManifest, imageManifestFile, REQUIRED_RUNTIME_IMAGE_KEYS)
def resolvedContainerRegistry = normalizeParamValue(params.container_registry, imageManifest.defaults.registry.toString())
def resolvedContainerNamespace = normalizeParamValue(params.container_namespace, imageManifest.defaults.namespace.toString())
def resolvedContainerImages = buildContainerImageMap(
    imageManifest,
    REQUIRED_RUNTIME_IMAGE_KEYS,
    resolvedContainerRegistry,
    resolvedContainerNamespace
)

// Schema-generated help (params, types, defaults, and descriptions all come
// from nextflow_schema.json). Note: -profile is a Nextflow core option, not a
// pipeline param, so it is documented in README.md rather than the schema.
if (params.help) {
    log.info paramsHelp(command: "nextflow run main.nf -profile docker --input_file <csv> --email <ncbi-email>")
    exit 0
}

// Declarative parameter validation against nextflow_schema.json. This enforces
// the checks that were previously hand-rolled: --email is required, --cpus (and
// the other integer params) must be integers, and any unrecognized param is
// reported. Replaces the former `if (params.x == '') error(...)` cascade.
validateParameters()

// Resolve this default after command-line parameters have been applied so that
// `--outdir custom-results` implies `custom-results/reference_genomes`. Keep it
// as an explicit value: mutating params here does not reliably propagate the
// new value into included modules.
def resolvedReferenceCache = normalizeParamValue(
    params.reference_cache,
    "${params.outdir}/reference_genomes"
)

// Residual cross-field check that a JSON schema cannot express: the pipeline
// needs EITHER --input_file OR (--sra_accession AND --identifier). nf-schema
// validates each param independently but not this XOR-style dependency across
// three params, so it stays as explicit Groovy. (This single condition covers
// both "nothing provided" and "only one of accession/identifier provided".)
if ( params.input_file == '' && ( params.sra_accession == '' || params.identifier == '' ) ) {
    error("You must provide either an SRA accession number and identifier (--sra_accession and --identifier), or an input file (--input_file).")
}

// If both an input file and an individual SRA accession/identifier are given,
// only the input file is used.
if ( params.input_file != '' && ( params.sra_accession != '' || params.identifier != '' ) ) {
    log.warn("Both an input file and individual SRA accession and/or identifier are provided. Only the input file will be used for the pipeline.")
}

log.info("Using container images from ${resolvedContainerRegistry}/${resolvedContainerNamespace}")
log.info("Using reference genome cache at ${resolvedReferenceCache}")

include { get_srrs } from './nf_scripts/get_srrs' addParams(container_image: resolvedContainerImages['sra_parser'])
include { parse_srrs } from './nf_scripts/parse_srrs' addParams(container_image: resolvedContainerImages['sra_parser'])
include { download_fastq } from './nf_scripts/download_fastq' addParams(container_image: resolvedContainerImages['aria2'])
include { run_fasterq_dump } from './nf_scripts/run_fasterq_dump' addParams(container_image: resolvedContainerImages['sra_tools'])
include { run_pigz } from './nf_scripts/run_pigz' addParams(container_image: resolvedContainerImages['pigz'])
include { run_fastp } from './nf_scripts/run_fastp' addParams(container_image: resolvedContainerImages['fastp'])
include { download_fasta } from './nf_scripts/download_fasta' addParams(
    container_image: resolvedContainerImages['biopython'],
    reference_cache: resolvedReferenceCache
)
include { run_bowtie2 } from './nf_scripts/run_bowtie2' addParams(container_image: resolvedContainerImages['bowtie2'])
include { run_samtools } from './nf_scripts/run_samtools' addParams(container_image: resolvedContainerImages['samtools'])
include { run_bcftools } from './nf_scripts/run_bcftools' addParams(container_image: resolvedContainerImages['bcftools'])
include { run_qualimap } from './nf_scripts/run_qualimap' addParams(container_image: resolvedContainerImages['qualimap'])
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter' addParams(container_image: resolvedContainerImages['bcftools'])
// run_multiqc hardcodes its own biocontainer, so it needs no container_image param.
include { run_multiqc } from './nf_scripts/run_multiqc'

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

        download_fastq( sra_accessions_channel )
        
        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join( run_fasterq_dump.out.reverse_reads) )

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

        download_fastq( sra_accessions_channel )

        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join(run_fasterq_dump.out.reverse_reads) )

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

    // Aggregate every per-sample QC/stats artifact into one MultiQC report.
    // Mix the QC-producing outputs and collect() them into a single channel so
    // MultiQC runs once over all files (fastp JSON, bowtie2 align summary,
    // qualimap dir, bcftools stats).
    multiqc_files = run_fastp.out.fastp_json_report
        .mix( run_bowtie2.out.align_summary )
        .mix( run_qualimap.out.qualimap_results )
        .mix( run_bcftools.out.stats_files )
        .collect()

    run_multiqc( multiqc_files )
}
