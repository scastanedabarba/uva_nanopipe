process SUMMARIZE_COVERAGE {

    tag "coverage_summary"

    input:
    path coverage_dirs

    output:
    path "summary/coverage.csv", emit: coverage_summary
    path "summary/read_filtering.csv", emit: filtering_summary

    script:
    """
    mkdir -p summary

    echo "isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status" > summary/coverage.csv

    for d in ${coverage_dirs}; do
        if [[ -f "\$d/coverage.csv" ]]; then
            tail -n +2 "\$d/coverage.csv" >> summary/coverage.csv
        else
            echo "[WARNING] Missing coverage.csv in \$d" >&2
        fi
    done

    echo "isolate,step,number_of_reads,total_bases,mean_read_length,median_read_length,read_length_n50,status" > summary/read_filtering.csv

    for d in ${coverage_dirs}; do
        if [[ -f "\$d/read_filtering.csv" ]]; then
            tail -n +2 "\$d/read_filtering.csv" >> summary/read_filtering.csv
        else
            echo "[WARNING] Missing read_filtering.csv in \$d" >&2
        fi
    done
    """
}
