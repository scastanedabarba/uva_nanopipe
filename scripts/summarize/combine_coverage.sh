#!/bin/bash
set -euo pipefail

OUTDIR=""

usage() {
    echo "Usage:"
    echo "  combine_coverage.sh --outdir OUTDIR --coverage-csv files... --filtering-csv files..."
}

coverage_files=()
filtering_files=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir)
            OUTDIR="$2"
            shift 2
            ;;
        --coverage-csv)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                coverage_files+=("$1")
                shift
            done
            ;;
        --filtering-csv)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                filtering_files+=("$1")
                shift
            done
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing --outdir"
    usage
    exit 1
fi

mkdir -p "$OUTDIR"

COVERAGE_OUT="${OUTDIR}/coverage.csv"
FILTERING_OUT="${OUTDIR}/read_filtering.csv"

echo "isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status" > "$COVERAGE_OUT"
for f in "${coverage_files[@]}"; do
    if [[ -s "$f" ]]; then
        tail -n +2 "$f" >> "$COVERAGE_OUT"
    fi
done

echo "isolate,step,number_of_reads,total_bases,mean_read_length,median_read_length,read_length_n50,status" > "$FILTERING_OUT"
for f in "${filtering_files[@]}"; do
    if [[ -s "$f" ]]; then
        tail -n +2 "$f" >> "$FILTERING_OUT"
    fi
done

echo "[INFO] Combined coverage summary written to: $COVERAGE_OUT"
echo "[INFO] Combined filtering summary written to: $FILTERING_OUT"
