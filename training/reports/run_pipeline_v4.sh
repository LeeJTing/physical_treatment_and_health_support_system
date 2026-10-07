#!/usr/bin/env bash
# Pipeline v4 (8 Oct): second person (p02, 9 clips) added to the training data; every model reads
# only its exercise's rule inputs (experiment_features.json: second person 25 -> 75 % sit-to-stand,
# 78 -> 97 % abduction). Augmentation: 8 variants, 3 workers (only missing variants are made).
cd "/c/Users/KOH Family/FYP/physical_treatment_and_health_support_system"
PY=ai_server/.venv/Scripts/python
KEYS="sit_to_stand shoulder_abduction shoulder_flexion hip_abduction knee_extension"
quiet() { grep --line-buffered -av "^W0000\|^I0000\|^WARNING: Logging\|^INFO: \|inference_feedback"; }

echo "== check p02 clips"
$PY training/check_clips.py sit_to_stand shoulder_abduction shoulder_flexion 2>&1 | quiet | grep --line-buffered -a "p02\|OK,"

echo "== augment (8 variants, 3 workers)"
start=$(date +%s)
$PY training/augment.py sit_to_stand shoulder_abduction shoulder_flexion --variants 8 --workers 3 2>&1 | quiet \
  | grep --line-buffered -a "clips x\|\[.*/.*\]" | awk 'NR==1 || NR%10==0 {print; fflush()}'
echo "augment took $(( ($(date +%s) - start) / 60 )) min"

echo "== dataset"
$PY training/build_dataset.py $KEYS 2>&1 | quiet

for k in $KEYS; do
  echo "== cv $k (own clips, rule inputs)"
  $PY training/cross_validate.py $k --own-only --rule-inputs 2>&1 | quiet | grep --line-buffered -a "accuracy\|reps"
  echo "== train $k (rule inputs)"
  extra=""; [ "$k" = "shoulder_abduction" ] && extra="--own-only"
  $PY training/train.py $k $extra 2>&1 | quiet | grep --line-buffered -a '"accuracy"\|"f1"\|mistake_type_accuracy\|"n_test"\|"split"\|confusion matrix\|saved'
done
echo PIPELINE_DONE
