alter table public.biometric_reading add column source_device varchar(80);
alter table public.biometric_reading add constraint biometric_reading_source_device_check check (source_device is null or (source = 'IMPORT' and char_length(btrim(source_device)) between 1 and 80));
comment on column public.biometric_reading.source_device is 'Advertised source watch name for a direct Bluetooth import. Watch blood pressure is displayed as a wearable estimate.';
