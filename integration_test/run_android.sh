#!/usr/bin/env bash
# Runs the Chapter 5 Flutter integration tests on an Android emulator (9 Nov).
#
# Selecting a plan asks Android for the notification permission. That system dialog is outside
# the app, so Flutter integration_test cannot tap it; it is tested by the Maestro flow
# maestro/rem_01_permission_allowed.yaml instead. Here the permission is granted with adb as soon
# as `flutter test` has installed the app (it is uninstalled again at the end of the run).
#
# Needs: the emulator running, and the AI server on the computer at port 8000 with
# DEV_AUTH_BYPASS=true. Extra arguments go to flutter test, e.g. --name "TC-PLN-03 *".
set -u
DEVICE="${DEVICE:-emulator-5554}"
PKG=com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system

(
  for _ in $(seq 1 600); do
    if adb -s "$DEVICE" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null; then
      echo "[run_android] notification permission granted"
      exit 0
    fi
    sleep 0.5
  done
) &
GRANTER=$!

flutter test integration_test/app_test.dart -d "$DEVICE" \
  --dart-define=USE_FAKES=true --dart-define=AI_BASE_URL=http://10.0.2.2:8000 "$@"
STATUS=$?
kill "$GRANTER" 2>/dev/null
exit $STATUS
