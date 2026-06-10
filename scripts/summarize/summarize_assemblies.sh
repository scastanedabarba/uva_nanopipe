#!/bin/bash
set -euo pipefail

OUTDIR=""
AUTOCYCLER_DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir)
            OUTDIR="$2"
            shift 2
            ;;
        --autocycler-dirs)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                AUTOCYCLER_DIRS+=("$1")
                shift
            done
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$OUTDIR" || ${#AUTOCYCLER_DIRS[@]} -eq 0 ]]; then
    echo "[ERROR] Missing required argument" >&2
    exit 1
fi

mkdir -p "$OUTDIR"

OUT_TSV="${OUTDIR}/autocycler_assembly_summary.tsv"

# Header
autocycler table > "$OUT_TSV"

for d in "${AUTOCYCLER_DIRS[@]}"; do
    if [[ ! -d "$d" ]]; then
        echo "[WARNING] Autocycler directory not found, skipping: $d" >&2
        continue
    fi

    sample_name=$(basename "$(dirname "$d")")
    sample_name="${sample_name%_final}"

    autocycler table \
        -a "$d" \
        -n "$sample_name" \
        >> "$OUT_TSV"
done

echo "[INFO] Wrote Autocycler assembly summary: $OUT_TSV"
