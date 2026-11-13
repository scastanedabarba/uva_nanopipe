#!/usr/bin/env bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
set -euo pipefail
(($#==7)) || { echo 'Usage: dorado_prepare.slurm POD5_DIR RUN_DIR MAPPING KIT DORADO_BIN MODELS_DIR RUN_NAME' >&2;exit 2; }
RAW=$1; RUN_DIR=$2; MAPPING=$3; KIT=$4; DORADO=$5; MODELS_DIR=$6; RUN=$7
MODEL="$MODELS_DIR/dna_r10.4.1_e8.2_400bps_sup@v5.2.0"
module purge;module load miniforge;module use /project/som_infc_dis_mathers/modulefiles/;module load pod5
command -v pod5 >/dev/null; [[ -x $DORADO && -d $MODEL ]] || { echo 'Dorado or SUP model missing' >&2;exit 1; }
find "$MODELS_DIR" -maxdepth 1 -type d -name 'dna_r10.4.1_e8.2_5khz_stereo@*' | grep -q . || { echo 'No stereo model installed' >&2;exit 1; }
PREP="$RUN_DIR/basecalling/$RUN/work/preparation"; mkdir -p "$PREP/channel_split" "$PREP/batch_lists"
[[ -s $MAPPING ]] || { echo 'Missing mapping' >&2;exit 1; }
find "$RAW" -type f -name '*.pod5' | sort > "$PREP/pod5.list"
[[ -s $PREP/pod5.list ]] || { echo 'No POD5 files' >&2;exit 1; }
# Input fingerprint prevents reusing stale channel splits when raw POD5 inputs change.
python3 - "$PREP/pod5.list" "$PREP/input_fingerprint.new" <<'PY2'
import hashlib,sys
from pathlib import Path
h=hashlib.sha256()
for line in Path(sys.argv[1]).read_text().splitlines():
 p=Path(line);s=p.stat();h.update(f'{p.resolve()}\t{s.st_size}\t{s.st_mtime_ns}\n'.encode())
Path(sys.argv[2]).write_text(h.hexdigest()+'\n')
PY2
REUSE=0
if [[ -f $PREP/.preparation_complete && -s $PREP/input_fingerprint && -s $PREP/channel_pod5.list ]] && cmp -s "$PREP/input_fingerprint" "$PREP/input_fingerprint.new"; then
 REUSE=1
 while IFS= read -r f; do [[ -s $f ]] || { REUSE=0;break; };done < "$PREP/channel_pod5.list"
fi
if (( ! REUSE ));then
 rm -f "$PREP/.preparation_complete";rm -rf "$PREP/channel_split";mkdir -p "$PREP/channel_split"
 mapfile -t INPUTS < "$PREP/pod5.list"
 pod5 view "${INPUTS[@]}" --include 'read_id,channel' --output "$PREP/channel_summary.tsv"
 pod5 subset "${INPUTS[@]}" --summary "$PREP/channel_summary.tsv" --columns channel --threads "${SLURM_CPUS_PER_TASK:-8}" --force-overwrite --output "$PREP/channel_split"
 find "$PREP/channel_split" -type f -name '*.pod5' | sort > "$PREP/channel_pod5.list"
fi
[[ -s $PREP/channel_pod5.list ]] || { echo 'No channel POD5 files' >&2;exit 1; }
while IFS= read -r f;do [[ -s $f ]] || { echo "Missing prepared POD5: $f" >&2;exit 1; };done < "$PREP/channel_pod5.list"
# SUP uses one channel per batch, as in the validated original workflow.
rm -f "$PREP/batch_lists"/channel_batch.*
split -l 1 "$PREP/channel_pod5.list" "$PREP/batch_lists/channel_batch."
# Metadata provenance; final_summary may be absent in exported POD5-only datasets.
find "$RAW" -type f -name 'final_summary*.txt' | sort > "$PREP/final_summaries.list"
if [[ -s $PREP/final_summaries.list ]];then
 grep -h '^protocol=' $(cat "$PREP/final_summaries.list") | grep -F "$KIT" >/dev/null || { echo "Kit $KIT not found in final_summary metadata" >&2;exit 1; }
fi
printf 'KIT_NAME=%q\nMODEL_PATH=%q\nMODELS_DIR=%q\n' "$KIT" "$MODEL" "$MODELS_DIR" > "$PREP/preparation_config.sh"
{ echo -e 'field\tvalue';printf 'kit\t%s\nmodel\t%s\ndorado\t%s\nraw_pod5_count\t%s\nprepared_channels\t%s\nprepared_reused\t%s\n' "$KIT" "$MODEL" "$DORADO" "$(wc -l < "$PREP/pod5.list")" "$(wc -l < "$PREP/channel_pod5.list")" "$REUSE";"$DORADO" --version | sed 's/^/dorado_version\t/';pod5 --version 2>&1 | sed 's/^/pod5_version\t/'; } > "$PREP/provenance.tsv"
mv "$PREP/input_fingerprint.new" "$PREP/input_fingerprint";touch "$PREP/.preparation_complete"
echo "Prepared $(wc -l < "$PREP/channel_pod5.list") channels"
