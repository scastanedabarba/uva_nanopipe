nextflow.enable.dsl=2

include { COVERAGE } from './modules/local/coverage'
include { SUMMARIZE_COVERAGE } from './modules/local/summarize_coverage'
include { AUTOCYCLER_SUBSAMPLE } from './modules/local/autocycler_subsample'
include { AUTOCYCLER_ASSEMBLE } from './modules/local/autocycler_assemble'
include { AUTOCYCLER_WEIGHT } from './modules/local/autocycler_weight'
include { AUTOCYCLER_FINISH } from './modules/local/autocycler_finish'
include { SUMMARIZE_ASSEMBLIES } from './modules/local/summarize_assemblies'

workflow {

    // Validate input
    if (params.input == null) {
        error "Please provide an input CSV with --input"
    }

    if (!(params.step in ['prep', 'assembly'])) {
        error "Specify --step prep or --step assembly"
    }

    // Create input channel from linelist
    samples_ch = Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            tuple(
                row.Isolate,
                file(row.Reads)
            )
        }

    // Preparation and assembly are separate Nextflow executions.
    if (params.step == 'prep') {
        COVERAGE(samples_ch)
        SUMMARIZE_COVERAGE(COVERAGE.out.coverage_dir.collect())
    }
    else if (params.step == 'assembly') {
        // Read published preparation files, not paths from a previous work directory.
        // A reduced linelist can be used to assemble only selected isolates.
        prep_ch = samples_ch.map { isolate, original_reads ->
            def prep = file("${params.outdir}/coverage/${isolate}")
            def trimmed = file("${prep}/trimmed_reads/${isolate}.trimmed.fastq.gz")
            def genome = file("${prep}/genome_size/genome_size.txt")
            def coverage = file("${prep}/coverage.csv")
            [trimmed, genome, coverage].each { f ->
                if (!f.exists() || !f.isFile() || f.size() == 0)
                    error "Missing or empty prep output for ${isolate}: ${f}. Run --step prep first."
            }
            def gs = genome.text.trim()
            if (!(gs ==~ /[0-9]+/) || gs.toLong() <= 0L)
                error "Invalid genome size for ${isolate}: ${gs}"
            def lines = coverage.readLines()
            if (lines.size() < 2)
                error "Invalid coverage.csv for ${isolate}: ${coverage}"
            def fields = lines[1].split(',', -1)
            if (fields.size() < 7 || fields[0] != isolate || fields[6].trim() != 'OK')
                error "Prep QC status is not OK for ${isolate}: ${lines[1]}"
            if (!(fields[5].trim() ==~ /[0-9]+/) || fields[5].toInteger() <= 0)
                error "Invalid min_read_depth for ${isolate}: ${fields[5]}"
            tuple(isolate, trimmed, genome, coverage)
        }
        AUTOCYCLER_SUBSAMPLE(prep_ch)

    // Create assembly jobs for each assembler and subsample
    assembly_jobs_ch = AUTOCYCLER_SUBSAMPLE.out.subsample_result
        .flatMap { isolate, subsample_dir ->

            def genome_size_file =
                file("${subsample_dir}/genome_size.txt")

            params.assemblers.collectMany { assembler ->
                ['01', '02', '03', '04'].collect { sample_id ->
                    tuple(
                        isolate,
                        assembler,
                        sample_id,
                        file("${subsample_dir}/subsampled_reads/sample_${sample_id}.fastq"),
                        genome_size_file
                    )
                }
            }
        }

    // Run individual assemblies
    AUTOCYCLER_ASSEMBLE(
        assembly_jobs_ch
    )

    // Group assemblies by isolate once all expected assemblies are complete
    def assemblies_per_isolate =
        params.assemblers.size() * 4

    assembly_grouped_ch =
        AUTOCYCLER_ASSEMBLE.out.assembly_result
            .map { assembly_dir ->
                def isolate =
                    assembly_dir.parent.parent.baseName

                tuple(
                    isolate,
                    assembly_dir
                )
            }
            .groupTuple(
                by: 0,
                size: assemblies_per_isolate
            )

    // Match subsampled reads to completed assembly groups
    subsample_keyed_ch =
        AUTOCYCLER_SUBSAMPLE.out.subsample_result

    weight_input_ch =
        assembly_grouped_ch
            .join(subsample_keyed_ch)
            .map {
                isolate,
                assembly_dirs,
                subsample_dir ->

                tuple(
                    isolate,
                    assembly_dirs,
                    subsample_dir
                )
            }

    // Weight assemblies
    AUTOCYCLER_WEIGHT(
        weight_input_ch
    )

    // Generate final Autocycler consensus assemblies
    AUTOCYCLER_FINISH(
        AUTOCYCLER_WEIGHT.out.assemblies
    )

    // Summarize final assemblies
    SUMMARIZE_ASSEMBLIES(
        AUTOCYCLER_FINISH.out.final_dir_for_summary.collect()
    )
    }
}
