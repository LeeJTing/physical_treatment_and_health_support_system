# Watch readings retained at nearby timestamps

A reported missing blood-pressure result was present in the physical watch's
daily saved history. Bluetooth returned it, but the app's inclusive five-minute
duplicate filter could discard it beside the previous measurement. The importer
now identifies repeats by account, metric and exact original timestamp. Distinct
measurement times remain separate for pressure, glucose and weight, including
consecutive measurements with unchanged numerical values.

The bulk repository deduplicates identical incoming keys and relies on the
existing database unique constraint with conflict ignore. It no longer pre-reads
a broad time window. This avoids dropping new records, preserves the original
stored snapshot and import time on retries, and counts only inserted rows.
The fake repository uses the same identity rule. No database migration or server
change is required. Supabase's documented [upsert conflict handling](https://supabase.com/docs/reference/dart/upsert)
is used through the existing pinned client.

Verified on 20 November 2026:

- All **690 Flutter host tests passed**. Coverage includes consecutive records,
  exact retries, account and metric separation, UTC instants, sub-millisecond
  timestamps, original import times and the actual REST payload and returned count.
- Flutter analyzer: **no issues**.
- Maestro in the updated signed-in app: **passed in 46 seconds**, verifying save, visible recovered readings and a repeat check with no new records. A further **16-second** Maestro check verified the specific original missing timestamp after a server reread. The app was updated in place and its watch connection restored.
- The device runner now prebuilds and verifies the isolated APK before launching Flutter tests, as well as disabling uninstall. PowerShell syntax checks passed.
- Physical KS02 Pro / HONOR LLY-NX1 native Integration Test: **passed in 18 seconds**.
  It retained 61 valid returned records in disposable storage, kept all four
  returned pressure records matching the reported values, and added zero on repeat.
  The SDK reported daily-history protocol 5 and no separate manual-history reader.

The sync status now says “No new saved watch records” instead of implying that
every measurement displayed on the watch has already been delivered. Capability
and count diagnostics are returned by the native reader; saved PINs remain private.
Actual transfer time and the firmware's saved-history granularity still apply.

The first diagnostic exposed a Flutter tooling cleanup problem: an application
package inferred before rebuilding the suffixed test APK could refer to the normal
app at cleanup. The normal app was restored and the user signed in again. Device
test commands and the runner now pass `--no-uninstall`. The protected rerun checked
that the normal package remained installed. This flag is required for future runs.

Live diagnostic logs contain health data and remain under ignored
`build/watch-sync-diagnostic-2026-11-20/`. Detailed raw-value logging requires an
explicit test define. No raw watch history is published in this evidence folder.
