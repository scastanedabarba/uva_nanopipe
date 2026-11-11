process AUTOCYCLER_SUBSAMPLE {

    tag "${isolate}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    tuple val(isolate),
          path(reads),
          path(genome_size),
          path(coverage_csv)

    output:
    tuple val(isolate),
          path("${isolate}/subsample"),
          emit: subsample_result

    script:
    """
    min_read_depth=\$(awk -F',' 'NR==2 {print \$6}' "${coverage_csv}")

    ${projectDir}/bin/uva_nanopipe autocycler-subsample \
        --isolate "${isolate}" \
        --reads "${reads}" \
        --genome-size "${genome_size}" \
        --min-read-depth "\${min_read_depth}" \
        --outdir "${isolate}/subsample" \
        --keep-subsampled-reads ${params.keep_subsampled_reads}
    """
}
