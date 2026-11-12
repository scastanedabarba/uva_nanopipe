process RECORD_ASSEMBLY_INPUT {
    tag 'assembly_manifest_record'
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    path manifest

    output:
    path 'assembly_parameters_used.csv'

    script:
    """
    cp "${manifest}" assembly_parameters_used.csv
    """
}
