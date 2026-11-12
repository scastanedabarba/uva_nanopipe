process AUTOCYCLER_SUBSAMPLE {

    tag "${isolate}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    tuple val(isolate),
          path(reads),
          val(genome_size),
          val(min_read_depth)

    output:
    tuple val(isolate),
          path("${isolate}/subsample"),
          emit: subsample_result

    script:
    """
    printf "%s\n" "${genome_size}" > genome_size.txt

    ${projectDir}/bin/uva_nanopipe autocycler-subsample \
        --isolate "${isolate}" \
        --reads "${reads}" \
        --genome-size genome_size.txt \
        --min-read-depth "${min_read_depth}" \
        --outdir "${isolate}/subsample" \
        --keep-subsampled-reads ${params.keep_subsampled_reads}
    """
}
