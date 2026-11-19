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
