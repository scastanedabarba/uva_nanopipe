process SUMMARIZE_ASSEMBLIES {
    publishDir "${params.outdir}/summary", mode: 'copy'

    tag "assembly_summary"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    path final_dirs

    output:
    path "autocycler_assembly_summary.tsv", emit: summary

    script:
    """
    ${projectDir}/bin/uva_nanopipe summarize-assemblies \
        --outdir . \
        --autocycler-dirs ${final_dirs.join('/autocycler_out ')}/autocycler_out
    """
}
