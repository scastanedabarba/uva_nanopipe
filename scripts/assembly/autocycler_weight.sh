#!/bin/bash
set -euo pipefail

ISOLATE=""
ASSEMBLIES_IN=""
OUTDIR=""
SUBSAMPLED_READS_DIR=""
KEEP_SUBSAMPLED_READS="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate) ISOLATE="$2"; shift 2 ;;
        --assemblies-in) ASSEMBLIES_IN="$2"; shift 2 ;;
        --subsampled-reads-dir) SUBSAMPLED_READS_DIR="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --keep-subsampled-reads) KEEP_SUBSAMPLED_READS="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISOLATE" || -z "$ASSEMBLIES_IN" || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument"
    exit 1
fi

mkdir -p "$OUTDIR/assemblies"

find "$ASSEMBLIES_IN" -name "*.fasta" -type f -exec cp {} "$OUTDIR/assemblies/" \;

shopt -s nullglob

for f in "$OUTDIR"/assemblies/plassembler*.fasta; do
    sed -i 's/circular=True/circular=True Autocycler_cluster_weight=2/' "$f"
done

for f in "$OUTDIR"/assemblies/canu*.fasta "$OUTDIR"/assemblies/flye*.fasta; do
    sed -i 's/^>.*$/& Autocycler_consensus_weight=2/' "$f"
done

shopt -u nullglob

if [[ "$KEEP_SUBSAMPLED_READS" == "true" && -n "$SUBSAMPLED_READS_DIR" && -d "$SUBSAMPLED_READS_DIR" ]]; then
    mkdir -p "$OUTDIR/subsampled_reads"
    cp "$SUBSAMPLED_READS_DIR"/*.fastq "$OUTDIR/subsampled_reads/" || true
fi

echo "[INFO] Weighted assemblies written to $OUTDIR/assemblies"
