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

    // Filter reads, estimate genome size, and calculate coverage
    COVERAGE(samples_ch)

    // Summarize coverage across isolates
    SUMMARIZE_COVERAGE(
        COVERAGE.out.coverage_dir.collect()
    )

    // Subsample reads for Autocycler
    AUTOCYCLER_SUBSAMPLE(
        COVERAGE.out.subsample_input
    )

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
