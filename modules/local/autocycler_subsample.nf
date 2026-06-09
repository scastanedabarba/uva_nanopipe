process AUTOCYCLER_SUBSAMPLE {

    tag "${coverage_dir.baseName}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    path coverage_dir

    output:
    path "${coverage_dir.baseName}/subsample", emit: subsample_dir

    script:
    """
    isolate="${coverage_dir.baseName}"
    reads="${coverage_dir}/trimmed_reads/\${isolate}.trimmed.fastq.gz"
    genome_size="${coverage_dir}/genome_size/genome_size.txt"
    min_read_depth=\$(awk -F',' 'NR==2 {print \$6}' "${coverage_dir}/coverage.csv")

    ${projectDir}/bin/uva_nanopipe autocycler-subsample \
        --isolate "\${isolate}" \
        --reads "\${reads}" \
        --genome-size "\${genome_size}" \
        --min-read-depth "\${min_read_depth}" \
        --outdir "\${isolate}/subsample" \
        --keep-subsampled-reads ${params.keep_subsampled_reads}
    """
}
