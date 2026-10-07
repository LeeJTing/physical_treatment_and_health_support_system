#!/usr/bin/env bash
# Pipeline v3 (7 Oct): hip_abduction + knee_extension clips added (trunk_lean left out, being
# re-recorded, imported 19:40) and augmentation widened from 4 to 8 variants per clip. 3 worker processes.
cd "/c/Users/KOH Family/FYP/physical_treatment_and_health_support_system"
PY=ai_server/.venv/Scripts/python
KEYS="sit_to_stand shoulder_abduction shoulder_flexion hip_abduction knee_extension"
quiet() { grep --line-buffered -av "^W0000\|^I0000\|^WARNING: Logging\|^INFO: \|inference_feedback"; }

echo "== check hip_abduction (after the rep fix and the new trunk_lean clips)"
grep -a "OK,\|^  " training/reports/check_hip_log.txt | tail -5
echo "== check knee_extension"
grep -a "OK,\|^  .*knee" training/reports/check_hip_knee_log.txt | tail -5

for k in $KEYS; do   # keep the 4-variant cross-validation results for comparison
  [ -f training/reports/cv_${k}_own.json ] && cp training/reports/cv_${k}_own.json training/reports/cv_${k}_own_aug4.json
done

echo "== augment (8 variants, 3 workers)"
start=$(date +%s)
$PY training/augment.py $KEYS --variants 8 --workers 3 2>&1 | quiet | grep --line-buffered -a "clips x\|\[.*/.*\]" | awk 'NR==1 || NR%25==0 {print; fflush()}'
echo "augment took $(( ($(date +%s) - start) / 60 )) min"

echo "== dataset"
$PY training/build_dataset.py $KEYS 2>&1 | quiet

for k in $KEYS; do
  echo "== cv $k (own clips, 8 variants)"
  $PY training/cross_validate.py $k --own-only 2>&1 | quiet | grep -a "accuracy\|reps"
  echo "== train $k"
  $PY training/train.py $k 2>&1 | quiet | grep -a '"accuracy"\|"f1"\|mistake_type_accuracy\|"n_test"\|confusion matrix\|saved'
done
echo PIPELINE_DONE
