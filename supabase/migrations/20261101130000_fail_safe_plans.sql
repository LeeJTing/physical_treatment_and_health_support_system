-- M700: a diet plan generated under the fail-safe limits (UC900 E1, the profile cannot be read)
-- has no stored safety_limit row to point at, so the link is optional. The app stores such a plan
-- with safety_limit_id null (SafetyLimit.failSafeId in the app).
alter table public.diet_plan alter column safety_limit_id drop not null;

-- M700: the meal-images bucket takes only what the app uploads (JPEG or PNG, at most 10 MB).
-- Skipped where there is no storage schema (tests/verify_schema.py).
do $$
begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets
       set file_size_limit = 10485760,
           allowed_mime_types = array['image/jpeg', 'image/png']
     where id = 'meal-images';
  end if;
end $$;
