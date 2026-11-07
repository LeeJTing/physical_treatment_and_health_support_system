-- Height and weight limits = the largest ever recorded (Elwin, 14 Oct; Guinness World Records):
-- tallest, Robert Wadlow 272 cm; heaviest, Jon Brower Minnoch about 635 kg. Before: 250 cm, 300 kg.
-- Same limits in the app (AppConstants.heightMax, weightMax). The minimums do not change.
-- numeric(5,2) holds up to 999.99 and bmi numeric(4,1) up to 999.9 (635 kg at 80 cm = 992.2).
--
-- Run in the Supabase SQL Editor (Elwin), or supabase db push.

begin;

alter table public.health_profile drop constraint if exists health_profile_weight_kg_check;
alter table public.health_profile drop constraint if exists health_profile_height_cm_check;

alter table public.health_profile
  add constraint health_profile_weight_kg_check check (weight_kg between 20 and 635),
  add constraint health_profile_height_cm_check check (height_cm between 80 and 272);

commit;
