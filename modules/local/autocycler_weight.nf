process AUTOCYCLER_WEIGHT {

    tag "${isolate}"
    
    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    tuple val(isolate), path(assembly_dirs), path(subsample_dir)

    output:
    path "${isolate}/drafts", emit: drafts_dir

    script:
    """
    ${projectDir}/bin/uva_nanopipe autocycler-weight \
        --isolate ${isolate} \
        --assemblies-in "${assembly_dirs}" \
        --subsampled-reads-dir "${subsample_dir}/subsampled_reads" \
        --outdir ${isolate}/drafts \
        --keep-subsampled-reads ${params.keep_subsampled_reads}
    """
}
