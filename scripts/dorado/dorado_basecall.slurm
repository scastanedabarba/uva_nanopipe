#!/usr/bin/env bash
#SBATCH --partition=gpu
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=100G
#SBATCH --time=2-00:00:00
set -euo pipefail
(($#==4)) || { echo 'Usage: dorado_basecall.slurm RUN_DIR DORADO_BIN MODELS_DIR RUN_NAME' >&2;exit 2; }
RUN_DIR=$1;DORADO=$2;MODELS_DIR=$3;RUN=$4;OUT="$RUN_DIR/basecalling/$RUN";PREP="$OUT/work/preparation";SUM="$RUN_DIR/summary/$RUN"
module purge;module load miniforge;module use /project/som_infc_dis_mathers/modulefiles/;module load samtools;module load pod5
[[ -f $PREP/.preparation_complete ]] || { echo 'Preparation not complete' >&2;exit 1; }
source "$PREP/preparation_config.sh"
[[ -x $DORADO && -d $MODEL_PATH ]] || { echo 'Dorado or model missing' >&2;exit 1; }
mkdir -p "$OUT/work/chunks" "$OUT/work/channel_batches" "$OUT/work/failed_batches" "$SUM"
mapfile -t BATCHES < <(find "$PREP/batch_lists" -maxdepth 1 -name 'channel_batch.*' -type f | sort)
((${#BATCHES[@]}>0)) || { echo 'No batch lists' >&2;exit 1; }
touch "$OUT/basecalling.commands.txt"
valid(){ [[ -s $1 ]] && samtools quickcheck -u "$1" >/dev/null 2>&1; }
for batch in "${BATCHES[@]}";do
 name=$(basename "$batch");chunk="$OUT/work/chunks/$name.duplex.bam";log="$OUT/work/chunks/$name.duplex.log";stage="$OUT/work/channel_batches/$name/pod5"
 if valid "$chunk";then echo "Reuse $name";continue;fi
 rm -f "$chunk";mkdir -p "$stage"
 while IFS= read -r f;do [[ -s $f ]] || { echo "Missing $f" >&2;exit 1; };ln -sf "$(realpath "$f")" "$stage/";done < "$batch"
 success=0
 for attempt in 1 2 3 4 5;do
  echo "Attempt $attempt $name" >> "$log";rm -f "$chunk"
  set +e
  printf '%q ' "$DORADO" duplex --device cuda:0 --batchsize 32 --models-directory "$MODELS_DIR" --recursive -v -v "$MODEL_PATH" "$stage" >> "$OUT/basecalling.commands.txt"
  printf '> %q 2>> %q\n' "$chunk" "$log" >> "$OUT/basecalling.commands.txt"
  "$DORADO" duplex --device cuda:0 --batchsize 32 --models-directory "$MODELS_DIR" --recursive -v -v "$MODEL_PATH" "$stage" > "$chunk" 2>> "$log"
  rc=$?
  set -e
  if valid "$chunk" && { ((rc==0)) || { grep -q '> Finished in' "$log" && grep -q '> Simplex reads basecalled:' "$log" && grep -q '> Duplex reads basecalled:' "$log"; }; };then success=1;break;fi
 done
 if (( ! success ));then
  mkdir -p "$OUT/work/failed_batches/$name";cp "$batch" "$OUT/work/failed_batches/$name/batch.list";cp "$log" "$OUT/work/failed_batches/$name/dorado.log"
  echo "Failed $name after five attempts" >&2;exit 1
 fi
 # Keep staged channel links and all chunk files for later storage review.
done
mapfile -t CHUNKS < <(find "$OUT/work/chunks" -maxdepth 1 -name '*.duplex.bam' -type f | sort -V)
((${#CHUNKS[@]}==${#BATCHES[@]})) || { echo 'Chunk count mismatch' >&2;exit 1; }
for f in "${CHUNKS[@]}";do valid "$f" || { echo "Invalid chunk $f" >&2;exit 1; };done
if ! valid "$OUT/duplex.bam";then
 samtools cat -@ "${SLURM_CPUS_PER_TASK:-16}" -o "$OUT/duplex.bam.tmp" "${CHUNKS[@]}"
 valid "$OUT/duplex.bam.tmp" || { echo 'Invalid merged BAM' >&2;exit 1; }
 mv "$OUT/duplex.bam.tmp" "$OUT/duplex.bam"
fi
"$DORADO" summary "$OUT/duplex.bam" > "$OUT/duplex_summary.tsv"
samtools view -H "$OUT/duplex.bam" | grep '^@RG' > "$OUT/read_groups.tsv" || true
samtools view -H "$OUT/duplex.bam" | grep -o 'basecall_model=[^ ]*' | sort -u > "$OUT/models_used.txt" || true
# Remove simplex parents of duplex consensus reads; preserve dx=0 and dx=1.
samtools view -h "$OUT/duplex.bam" | awk '/^@/{print;next}{for(i=12;i<=NF;i++)if($i=="dx:i:0"||$i=="dx:i:1"){print;break}}' | samtools view -@ "${SLURM_CPUS_PER_TASK:-16}" -b -o "$OUT/demux_input.bam.tmp" -
valid "$OUT/demux_input.bam.tmp" || { echo 'Invalid demux BAM' >&2;exit 1; }
mv "$OUT/demux_input.bam.tmp" "$OUT/demux_input.bam"
printf '%q ' "$DORADO" summary "$OUT/duplex.bam" >> "$OUT/basecalling.commands.txt"
printf '> %q\n' "$OUT/duplex_summary.tsv" >> "$OUT/basecalling.commands.txt"
python3 "$(dirname "$0")/duplex_metrics.py" "$OUT/duplex.bam" "$SUM/$RUN.duplex_metrics.tsv"
touch "$OUT/.basecalling_complete"
echo "Completed basecalling: $OUT/duplex.bam"
