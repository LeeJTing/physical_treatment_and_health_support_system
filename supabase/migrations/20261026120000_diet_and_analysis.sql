-- 26 Oct 2026: what Jun Ting's modules (M200, M400, M700) need beyond the core schema.
-- Run in the SQL Editor after the earlier migrations, then supabase/seed/seed_food.sql.
-- Safe to run again.
--
-- 1. model_version columns hold the full version of each model ("food-clip-vitb16-head-1",
--    "diet-planner-1.0+pref-logreg-1", "analysis-1.0+health-score-1.0+risk-gbdt-nhanes-1.0"),
--    longer than the 20 characters of the ERD (FR400_007, FR400_029, FR700_008, FR700_043).
-- 2. health_analysis.score_band takes the bands of UC600 C12: Good, Fair, Needs attention, At risk.
-- 3. food_item gets food_key (the label the food recogniser and the planner use for the food,
--    FoodRecognitionService.mapToCatalogue), plan_role and meal_slots (how the planner may use it).
-- 4. The dietary restriction list is completed (Table 4.88 only gave examples): fish, egg, milk,
--    gluten, no beef. The codes are the restriction tags of the food catalogue.
-- 5. Private storage bucket "meal-images" for confirmed meal photos (FR700_009, FR700_016), one
--    folder per account; only on a real Supabase project (the local schema test has no storage).

alter table public.forecast        alter column model_version type varchar(60);
alter table public.health_analysis alter column model_version type varchar(60);
alter table public.meal_log        alter column model_version type varchar(60);
alter table public.diet_plan       alter column model_version type varchar(60);

alter table public.health_analysis drop constraint if exists health_analysis_score_band_check;
update public.health_analysis set score_band = case score_band
  when 'EXCELLENT' then 'GOOD' when 'POOR' then 'AT_RISK' else score_band end;
alter table public.health_analysis add constraint health_analysis_score_band_check
  check (score_band in ('GOOD', 'FAIR', 'NEEDS_ATTENTION', 'AT_RISK'));

alter table public.food_item add column if not exists food_key   varchar(40);
alter table public.food_item add column if not exists plan_role  varchar(10) not null default 'meal';
alter table public.food_item add column if not exists meal_slots text[]      not null default '{}';
create unique index if not exists food_item_food_key_idx on public.food_item (food_key);
alter table public.food_item drop constraint if exists food_item_plan_role_check;
alter table public.food_item add constraint food_item_plan_role_check
  check (plan_role in ('meal', 'staple', 'protein', 'veg', 'fruit', 'drink', 'snack', 'dessert', 'soup'));

insert into public.dietary_restriction (restriction_id, restriction_code, restriction_name, restriction_type) values
  (6,  'FISH',   'Fish allergy',                'ALLERGY'),
  (7,  'EGG',    'Egg allergy',                 'ALLERGY'),
  (8,  'MILK',   'Milk or lactose intolerance', 'INTOLERANCE'),
  (9,  'GLUTEN', 'Gluten (wheat) intolerance',  'INTOLERANCE'),
  (10, 'BEEF',   'No beef',                     'RELIGIOUS')
on conflict (restriction_id) do nothing;

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public) values ('meal-images', 'meal-images', false)
      on conflict (id) do nothing;
    drop policy if exists "owner reads meal images" on storage.objects;
    drop policy if exists "owner adds meal images" on storage.objects;
    drop policy if exists "owner updates meal images" on storage.objects;
    drop policy if exists "owner deletes meal images" on storage.objects;
    create policy "owner reads meal images" on storage.objects for select to authenticated
      using (bucket_id = 'meal-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy "owner adds meal images" on storage.objects for insert to authenticated
      with check (bucket_id = 'meal-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy "owner updates meal images" on storage.objects for update to authenticated
      using (bucket_id = 'meal-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy "owner deletes meal images" on storage.objects for delete to authenticated
      using (bucket_id = 'meal-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
end $$;
