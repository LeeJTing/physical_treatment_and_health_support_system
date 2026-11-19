alter table public.biometric_reading add column imported_at timestamptz;
alter table public.biometric_reading add constraint biometric_reading_imported_at_check
  check (imported_at is null or source = 'IMPORT');
comment on column public.biometric_reading.imported_at is
  'Time this imported reading was first saved by HealthGuide. Null for manual readings and older imports whose import time was not recorded.';
