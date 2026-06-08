#!/bin/bash
set -euo pipefail

ISOLATE=""
READS=""
OUTDIR=""
THREADS=4
MAX_EST_READS=30000

usage() {
    echo "Usage:"
    echo "  calculate_coverage.sh \\"
    echo "    --isolate ISOLATE_ID \\"
    echo "    --reads READS.fastq.gz \\"
    echo "    --outdir OUTDIR \\"
    echo "    --threads 4 \\"
    echo "    --max-est-reads 30000"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate)
            ISOLATE="$2"
            shift 2
            ;;
        --reads)
            READS="$2"
            shift 2
            ;;
        --outdir)
            OUTDIR="$2"
            shift 2
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --max-est-reads)
            MAX_EST_READS="$2"
            shift 2
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

if [[ -z "$ISOLATE" || -z "$READS" || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument."
    usage
    exit 1
fi

TRIMDIR="${OUTDIR}/trimmed_reads"
GENOMESIZE_DIR="${OUTDIR}/genome_size"

TRIMMED_READS="${TRIMDIR}/${ISOLATE}.trimmed.fastq.gz"
GENOME_SIZE_READS="${GENOMESIZE_DIR}/${ISOLATE}.genome_size_reads.fastq.gz"
GENOME_SIZE_TXT="${GENOMESIZE_DIR}/genome_size.txt"

PRE_NANOSTAT="${TRIMDIR}/pre_trimming.nanostat.txt"
POST_NANOSTAT="${TRIMDIR}/post_trimming.nanostat.txt"

FILTERING_OUT="${OUTDIR}/read_filtering.csv"
COVERAGE_OUT="${OUTDIR}/coverage.csv"

mkdir -p "$TRIMDIR" "$GENOMESIZE_DIR"

write_empty_outputs() {
    status="$1"

    echo "isolate,step,number_of_reads,total_bases,mean_read_length,median_read_length,read_length_n50,status" > "$FILTERING_OUT"
    echo "${ISOLATE},pre-trimming,NA,NA,NA,NA,NA,${status}" >> "$FILTERING_OUT"
    echo "${ISOLATE},post-trimming,NA,NA,NA,NA,NA,${status}" >> "$FILTERING_OUT"

    echo "isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status" > "$COVERAGE_OUT"
    echo "${ISOLATE},NA,NA,NA,NA,NA,${status}" >> "$COVERAGE_OUT"

    echo "NA" > "$GENOME_SIZE_TXT"
}

parse_nanostat() {
    file="$1"
    step="$2"

    awk -v isolate="$ISOLATE" -v step="$step" '
        BEGIN { FS=":"; OFS="," }
        /Number of reads/ {
            val=$2; gsub(/[, ]/, "", val); gsub(/\.0$/, "", val); reads=val
        }
        /Total bases/ {
            val=$2; gsub(/[, ]/, "", val); gsub(/\.0$/, "", val); bases=val
        }
        /Mean read length/ {
            val=$2; gsub(/[, ]/, "", val); mean=val
        }
        /Median read length/ {
            val=$2; gsub(/[, ]/, "", val); median=val
        }
        /Read length N50/ {
            val=$2; gsub(/[, ]/, "", val); n50=val
        }
        END {
            print isolate, step, reads, bases, mean, median, n50, "OK"
        }
    ' "$file"
}

if [[ ! -f "$READS" ]]; then
    echo "[WARNING] Reads not found for ${ISOLATE}: $READS"
    write_empty_outputs "READS_NOT_FOUND"
    exit 0
fi

echo "[INFO] Running NanoStat pre-trimming: ${ISOLATE}"
NanoStat --fastq "$READS" -t "$THREADS" -n "$PRE_NANOSTAT"

echo "[INFO] Filtering reads with chopper: ${ISOLATE}"
gzip -dc "$READS" | chopper -q 10 -l 1000 | gzip > "$TRIMMED_READS"

if [[ ! -s "$TRIMMED_READS" ]]; then
    echo "[WARNING] Trimmed reads empty for ${ISOLATE}"
    write_empty_outputs "TRIMMED_READS_EMPTY"
    exit 0
fi

echo "[INFO] Running NanoStat post-trimming: ${ISOLATE}"
NanoStat --fastq "$TRIMMED_READS" -t "$THREADS" -n "$POST_NANOSTAT"

echo "isolate,step,number_of_reads,total_bases,mean_read_length,median_read_length,read_length_n50,status" > "$FILTERING_OUT"
parse_nanostat "$PRE_NANOSTAT" "pre-trimming" >> "$FILTERING_OUT"
parse_nanostat "$POST_NANOSTAT" "post-trimming" >> "$FILTERING_OUT"

filtered_reads=$(awk -F',' '$2 == "post-trimming" {print $3}' "$FILTERING_OUT")
total_bases=$(awk -F',' '$2 == "post-trimming" {print $4}' "$FILTERING_OUT")

if [[ "$filtered_reads" -gt "$MAX_EST_READS" ]]; then
    echo "[INFO] Downsampling to ${MAX_EST_READS} reads for Raven genome size estimation: ${ISOLATE}"
    seqtk sample -s100 "$TRIMMED_READS" "$MAX_EST_READS" | gzip > "$GENOME_SIZE_READS"
else
    echo "[INFO] Using all filtered reads for Raven genome size estimation: ${ISOLATE}"
    cp "$TRIMMED_READS" "$GENOME_SIZE_READS"
fi

echo "[INFO] Estimating genome size with Autocycler/Raven helper: ${ISOLATE}"
genome_size=$(timeout 8h autocycler helper genome_size \
    --reads "$GENOME_SIZE_READS" \
    --threads "$THREADS" \
    2>/dev/null | grep -Eo '[0-9]+' | tail -n 1 || true)

[[ -z "$genome_size" ]] && genome_size="NA"

echo "$genome_size" > "$GENOME_SIZE_TXT"

if [[ "$genome_size" == "NA" || "$genome_size" -le 0 ]]; then
    echo "isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status" > "$COVERAGE_OUT"
    echo "${ISOLATE},${filtered_reads},${total_bases},${genome_size},NA,NA,GENOME_SIZE_FAILED" >> "$COVERAGE_OUT"
    exit 0
fi

coverage_est=$(awk -v tb="$total_bases" -v gs="$genome_size" 'BEGIN {
    if (gs > 0 && tb > 0) printf "%.2f", tb / gs;
    else print "NA";
}')

min_read_depth=$(awk -v cov="$coverage_est" 'BEGIN {
    if (cov < 25) print 10;
    else print 25;
}')

echo "isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status" > "$COVERAGE_OUT"
echo "${ISOLATE},${filtered_reads},${total_bases},${genome_size},${coverage_est},${min_read_depth},OK" >> "$COVERAGE_OUT"

echo "[INFO] Coverage step complete: ${ISOLATE}"
