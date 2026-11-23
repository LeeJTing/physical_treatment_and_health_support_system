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

## Broader wearable discovery on 19 November 2026

The Bluetooth scanner now uses the Veepoo SDK's compatible-device discovery
instead of accepting only KS02/K202 advertised names. UI guidance asks users to
disconnect from the companion app before connecting through Bluetooth and explains
the Health Connect path for other wearable protocols. This does not establish
universal watch compatibility.

The updated native Integration Test passed in 1m 30s with the physical KS02 Pro:
11 blood pressure and 12 numerical glucose records returned, 18 saved after
validation and duplicate filtering, zero added on repeat, saved connection
restored and scheduled sync completed. The Health Connect weight fixture passed
again. Log: `build/watch-compatible-device.log`. Three targeted host watch tests
passed and changed-file analysis found no issues. The preceding full 665-test
suite remains the full-suite baseline.

Maestro passed the revised screen journey in 1m 26s. The new guidance screenshot
is embedded under WATCH-05 in report v27's Actual result cell. Local artifacts:
`build/e2e/watch-compatible-2026-11-19/`. Test storage was isolated and phone
rotation settings were restored. No additional physical watch model was tested;
compatible models require their own acceptance runs. Set `WATCH_TEST_NAME` to the
exact authorised test watch name when running the native target for another model.

## Tracking inspection, zoom and new imports on 20 November 2026

All **673 Flutter host tests passed**. The graph phone Integration Test passed in
19 seconds on the HONOR LLY-NX1 with the production Tracking view and disposable
fixtures. It covered blood pressure, glucose and weight, measured/import dates,
per-metric reading/import counts, clearing details in gaps, pinch zoom/reset,
unknown import dates on legacy records and a date range without readings.

Maestro `13_tracking_graph.yaml` passed in 49 seconds. It captured reading detail
popups for all three metrics, the cleared gap and a zoomed view. An earlier run
matched a zoom label merged into the accessibility parent; the zoom level now has
its own semantic container and spoken label. Rotation was restored to 1 / 0.
Artifacts are local under `build/e2e/tracking-graph-final-2026-11-20/`.
Phone logs: `build/tracking-graph-device.log`; final host log:
`build/tracking-graph-full-tests-final.log`. Table 5.22 in report v28 embeds the
pressure popup and zoom screenshots in the related Actual result cells.

The watch source is polled every 15 seconds while foregrounded, with overlapping
checks skipped. A simulated-source test returned a new record during scheduled
checks, verified immediate saving of the returned data, preserved the original
import time on duplicates and kept the selected past date range. Existing native
history communication remains covered by the earlier physical-watch runs; this
graph acceptance used synthetic records and did not establish real new-record
push delivery or real account cloud persistence.

Migration `20261119130555_biometric_import_time` added nullable `imported_at`;
existing records retain unknown dates. The remote column, constraint and RLS were
verified. Repository tests check counts from rows actually returned by the insert,
including a duplicate race returning zero, and confirm import metadata is omitted
from analysis inputs. Security advisors remained at the same two pre-existing
notices. No measurement-accuracy or closed-app background-sync claim is made.
