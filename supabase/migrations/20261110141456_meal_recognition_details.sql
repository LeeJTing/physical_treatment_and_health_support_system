-- Optional review metadata. Existing meals, ownership policies and nutrient snapshots stay intact.
alter table public.meal_item
  add column if not exists recognition_details jsonb;

alter table public.meal_item
  add constraint meal_item_recognition_details_object
  check (recognition_details is null or jsonb_typeof(recognition_details) = 'object');

comment on column public.meal_item.recognition_details is
  'Reviewed photo proposals: count/unit, estimated weight and normalised regions. Not a measured quantity or nutrition source.';
