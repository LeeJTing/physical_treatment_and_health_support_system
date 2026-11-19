# Recorded device results

See the [test record, screenshots and logs](../docs/testing/jt-device-2026-11-10/README.md).

15 Flutter integration cases and nine Maestro flows passed with isolated demo data. The record identifies dates, device, scope and remaining acceptance checks.

On 19 November 2026, the direct-watch acceptance target passed on the same HONOR
LLY-NX1 with a physical KS02 Pro, firmware 03.71.03. The final native test read
four blood pressure records, saved four in disposable repositories and added
zero on a repeated import. The host suite passed 663 tests and changed-file
analysis found no issues.

The explicit Maestro `12_watch_import.yaml` flow also passed, covering scan,
device selection, review, confirmed import and the device label in Tracking.
This run used portrait orientation. Earlier selector attempts encountered
orientation-dependent accessibility bounds. The test restored the phone's
original rotation settings after completion.

Local run logs and screenshots are under `build/e2e/watch-2026-11-19-portrait/`.
The native acceptance log is `build/watch-device-test-final.log`. The screenshots
show physical watch estimates saved in an isolated account alongside its demo
baseline. They establish device communication and app behavior. Measurement
accuracy and authenticated cloud storage require separate acceptance checks.

## Automatic watch sync and glucose on 19 November 2026

The extended physical-watch Flutter Integration Test passed on the HONOR LLY-NX1.
KS02 Pro firmware 03.71.03 returned nine blood pressure and ten numerical glucose
records. Validation and the repository's five-minute duplicate policy saved 14;
reimporting the same snapshot added zero. A new view model restored the encrypted
connection and a scheduled tick reconnected and read the watch. A synthetic weight
record verified the separate Health Connect adapter path. No physical scale was
used. The native log is `build/watch-auto-device-final.log`.

The full host suite passed **665 tests**. Final targeted watch tests passed three
cases, covering validation, retries, saved connections, all three app metrics and
discarding a late response after disconnection. Changed-file analysis found no issues.

Maestro's updated `12_watch_import.yaml` passed in 2m 3s with isolated app storage,
covering scan, review, enabling automatic sync, a second read reporting Up to date
and the source label in Tracking. An earlier run encountered a Bluetooth reconnect
failure; it retained the saved connection and showed the retry message. The repeat
passed. A separate 59-second Maestro evidence pass verified scrolling to individual
numerical glucose records after they were given separate accessibility containers.
Phone rotation settings were restored after each run.

Local artifacts are in `build/e2e/watch-auto-final-2026-11-19/` and
`build/e2e/watch-glucose-evidence-2026-11-19/`. The report's WATCH-03 and WATCH-04
Actual result cells contain the connected/synced card and numerical glucose
screenshots. Raw watch screenshots stay local because they contain health readings.

Automatic checks run every minute while HealthGuide is open, on opening and on
returning to the foreground. This implementation does not run a closed-app
background service. BP and glucose remain watch estimates. Weight comes from a
compatible Health Connect source or manual entry; the watch profile weight is
excluded. These tests establish app behavior and device communication, without
establishing measurement accuracy or real account cloud persistence.
