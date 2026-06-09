#!/bin/bash
set -euo pipefail

ISOLATE=""
ASSEMBLIES_IN=()
OUTDIR=""
SUBSAMPLED_READS_DIR=""
KEEP_SUBSAMPLED_READS="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate)
            ISOLATE="$2"
            shift 2
            ;;
        --assemblies-in)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                ASSEMBLIES_IN+=("$1")
                shift
            done
            ;;
        --subsampled-reads-dir)
            SUBSAMPLED_READS_DIR="$2"
            shift 2
            ;;
        --outdir)
            OUTDIR="$2"
            shift 2
            ;;
        --keep-subsampled-reads)
            KEEP_SUBSAMPLED_READS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$ISOLATE" || ${#ASSEMBLIES_IN[@]} -eq 0 || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument" >&2
    exit 1
fi

mkdir -p "$OUTDIR/assemblies"

for x in "${ASSEMBLIES_IN[@]}"; do
    resolved=$(readlink -f "$x" || true)

    if [[ -z "$resolved" ]]; then
        echo "[WARNING] Could not resolve assembly input: $x" >&2
        continue
    fi

    if [[ -f "$resolved" && "$resolved" == *.fasta ]]; then
        cp "$resolved" "$OUTDIR/assemblies/"
    elif [[ -d "$resolved" ]]; then
        find "$resolved" -name "*.fasta" -type f -exec cp {} "$OUTDIR/assemblies/" \;
    else
        echo "[WARNING] Assembly input not found or not FASTA: $x -> $resolved" >&2
    fi
done

n_assemblies=$(find "$OUTDIR/assemblies" -name "*.fasta" -type f | wc -l)

if [[ "$n_assemblies" -eq 0 ]]; then
    echo "[ERROR] No FASTA files were copied into $OUTDIR/assemblies" >&2
    echo "[ERROR] Input assembly paths were:" >&2
    printf '  %s\n' "${ASSEMBLIES_IN[@]}" >&2
    exit 1
fi

echo "[INFO] Copied $n_assemblies FASTA assemblies into $OUTDIR/assemblies"

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
