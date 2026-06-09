#!/bin/bash
set -euo pipefail

ISOLATE=""
READS=""
GENOME_SIZE_FILE=""
MIN_READ_DEPTH=""
OUTDIR=""
KEEP_SUBSAMPLED_READS="true"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate) ISOLATE="$2"; shift 2 ;;
        --reads) READS="$2"; shift 2 ;;
        --genome-size) GENOME_SIZE_FILE="$2"; shift 2 ;;
        --min-read-depth) MIN_READ_DEPTH="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --keep-subsampled-reads) KEEP_SUBSAMPLED_READS="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISOLATE" || -z "$READS" || -z "$GENOME_SIZE_FILE" || -z "$MIN_READ_DEPTH" || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument"
    exit 1
fi

GENOME_SIZE=$(cat "$GENOME_SIZE_FILE")

mkdir -p "$OUTDIR"

autocycler subsample \
    --reads "$READS" \
    --out_dir "$OUTDIR/subsampled_reads" \
    --min_read_depth "$MIN_READ_DEPTH" \
    --genome_size "$GENOME_SIZE" \
    2> "$OUTDIR/autocycler_subsample.stderr"

echo "$GENOME_SIZE" > "$OUTDIR/genome_size.txt"
echo "$MIN_READ_DEPTH" > "$OUTDIR/min_read_depth.txt"
echo "$KEEP_SUBSAMPLED_READS" > "$OUTDIR/keep_subsampled_reads.txt"
