-- "Foods I cannot eat" becomes a list of food names, and the food catalogue gets the nutrients the
-- condition rules and the plan targets use (food-catalogue-2.0, built from USDA FoodData Central
-- ingredients, standard recipes and laboratory analyses of Malaysian foods).
--
-- 1. dietary_restriction: new type FOOD, a food_group for the profile screen, is_active. The diet
--    labels VEGAN, VEGETARIAN, HALAL and SHELLFISH are no longer offered (is_active = false; the rows
--    stay because old suitability verdicts point at them). PEANUT, FISH, EGG, MILK, GLUTEN and BEEF
--    keep their ids as food names; 30 food names are added (ids 11-40), e.g. ONION, GARLIC, PORK.
-- 2. A patient who had chosen a diet label now has the food names it rules out
--    (HALAL -> PORK, LARD, ALCOHOL; SHELLFISH -> PRAWN, SHRIMP_PASTE, CRAB, SQUID, MOLLUSC;
--    VEGETARIAN -> meat, poultry, fish and seafood; VEGAN -> those plus EGG and MILK).
-- 3. food_item: total sugars, saturated fat, fibre, potassium, phosphorus, calcium, caffeine per
--    100 g; whether the food needs two hands (arm limitation); a pregnancy caution; the data source.
--    Run seed_food.sql afterwards to fill them and to rebuild food_restriction from the recipes.
-- Safe to run more than once.

begin;

alter table public.dietary_restriction drop constraint if exists dietary_restriction_restriction_type_check;
alter table public.dietary_restriction add constraint dietary_restriction_restriction_type_check
  check (restriction_type in ('ALLERGY', 'INTOLERANCE', 'DIET', 'RELIGIOUS', 'FOOD'));
alter table public.dietary_restriction alter column restriction_name type varchar(60);
alter table public.dietary_restriction add column if not exists food_group varchar(40);
alter table public.dietary_restriction add column if not exists is_active boolean not null default true;

insert into public.dietary_restriction
  (restriction_id, restriction_code, restriction_name, restriction_type, food_group, is_active) values
  (11, 'PORK', 'Pork', 'FOOD', 'Meat, fish and seafood', true),
  (12, 'LARD', 'Lard (pork fat)', 'FOOD', 'Meat, fish and seafood', true),
  (10, 'BEEF', 'Beef', 'FOOD', 'Meat, fish and seafood', true),
  (13, 'MUTTON', 'Mutton or lamb', 'FOOD', 'Meat, fish and seafood', true),
  (14, 'CHICKEN', 'Chicken', 'FOOD', 'Meat, fish and seafood', true),
  (15, 'DUCK', 'Duck', 'FOOD', 'Meat, fish and seafood', true),
  (6, 'FISH', 'Fish (incl. fish sauce, fish balls)', 'FOOD', 'Meat, fish and seafood', true),
  (16, 'ANCHOVY', 'Anchovies (ikan bilis)', 'FOOD', 'Meat, fish and seafood', true),
  (17, 'PRAWN', 'Prawn or shrimp (incl. dried shrimp)', 'FOOD', 'Meat, fish and seafood', true),
  (18, 'SHRIMP_PASTE', 'Shrimp paste (belacan)', 'FOOD', 'Meat, fish and seafood', true),
  (19, 'CRAB', 'Crab', 'FOOD', 'Meat, fish and seafood', true),
  (20, 'SQUID', 'Squid or cuttlefish', 'FOOD', 'Meat, fish and seafood', true),
  (21, 'MOLLUSC', 'Clams, cockles or oyster sauce', 'FOOD', 'Meat, fish and seafood', true),
  (7, 'EGG', 'Egg', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (8, 'MILK', 'Milk and dairy (incl. condensed milk, ghee)', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (1, 'PEANUT', 'Peanut', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (22, 'TREE_NUT', 'Tree nuts (almond, cashew)', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (23, 'SOY', 'Soy (tofu, tempeh, soy sauce, soya milk)', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (24, 'SESAME', 'Sesame', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (25, 'BEANS', 'Beans and lentils (dhal, kacang)', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (9, 'GLUTEN', 'Wheat (gluten)', 'FOOD', 'Egg, dairy, nuts and grains', true),
  (26, 'ONION', 'Onion, shallot or spring onion', 'FOOD', 'Vegetables, fruit and others', true),
  (27, 'GARLIC', 'Garlic', 'FOOD', 'Vegetables, fruit and others', true),
  (28, 'CHILLI', 'Chilli', 'FOOD', 'Vegetables, fruit and others', true),
  (29, 'COCONUT', 'Coconut and coconut milk (santan)', 'FOOD', 'Vegetables, fruit and others', true),
  (30, 'MUSHROOM', 'Mushroom', 'FOOD', 'Vegetables, fruit and others', true),
  (31, 'TOMATO', 'Tomato', 'FOOD', 'Vegetables, fruit and others', true),
  (32, 'BRINJAL', 'Brinjal (eggplant)', 'FOOD', 'Vegetables, fruit and others', true),
  (33, 'POTATO', 'Potato', 'FOOD', 'Vegetables, fruit and others', true),
  (34, 'CORN', 'Corn', 'FOOD', 'Vegetables, fruit and others', true),
  (35, 'BANANA', 'Banana', 'FOOD', 'Vegetables, fruit and others', true),
  (36, 'MANGO', 'Mango', 'FOOD', 'Vegetables, fruit and others', true),
  (37, 'PINEAPPLE', 'Pineapple', 'FOOD', 'Vegetables, fruit and others', true),
  (38, 'DURIAN', 'Durian', 'FOOD', 'Vegetables, fruit and others', true),
  (39, 'ALCOHOL', 'Alcohol (incl. cooking wine)', 'FOOD', 'Vegetables, fruit and others', true),
  (40, 'CAFFEINE', 'Coffee or tea (caffeine)', 'FOOD', 'Vegetables, fruit and others', true)
on conflict (restriction_id) do update set
  restriction_code = excluded.restriction_code, restriction_name = excluded.restriction_name,
  restriction_type = excluded.restriction_type, food_group = excluded.food_group, is_active = true;

-- Old diet labels -> the food names they rule out.
create temporary table retired_map (old_id smallint, new_id smallint) on commit drop;
insert into retired_map (old_id, new_id) values
  (2, 17),
  (2, 18),
  (2, 19),
  (2, 20),
  (2, 21),
  (3, 11),
  (3, 12),
  (3, 10),
  (3, 13),
  (3, 14),
  (3, 15),
  (3, 6),
  (3, 16),
  (3, 17),
  (3, 18),
  (3, 19),
  (3, 20),
  (3, 21),
  (3, 7),
  (3, 8),
  (4, 11),
  (4, 12),
  (4, 10),
  (4, 13),
  (4, 14),
  (4, 15),
  (4, 6),
  (4, 16),
  (4, 17),
  (4, 18),
  (4, 19),
  (4, 20),
  (4, 21),
  (5, 11),
  (5, 12),
  (5, 39);

insert into public.profile_restriction (profile_id, restriction_id)
select distinct pr.profile_id, m.new_id
from public.profile_restriction pr join retired_map m on m.old_id = pr.restriction_id
on conflict do nothing;
delete from public.profile_restriction where restriction_id in (select old_id from retired_map);
delete from public.food_restriction where restriction_id in (select old_id from retired_map);
update public.dietary_restriction set is_active = false
where restriction_id in (select old_id from retired_map);

alter table public.food_item add column if not exists total_sugar_g_per_100g numeric(6,2) not null default 0;
alter table public.food_item add column if not exists sat_fat_g_per_100g     numeric(6,2) not null default 0;
alter table public.food_item add column if not exists fibre_g_per_100g       numeric(6,2) not null default 0;
alter table public.food_item add column if not exists potassium_mg_per_100g  numeric(7,2) not null default 0;
alter table public.food_item add column if not exists phosphorus_mg_per_100g numeric(7,2) not null default 0;
alter table public.food_item add column if not exists calcium_mg_per_100g    numeric(7,2) not null default 0;
alter table public.food_item add column if not exists caffeine_mg_per_100g   numeric(6,2) not null default 0;
alter table public.food_item add column if not exists needs_two_hands        boolean      not null default false;
alter table public.food_item add column if not exists two_hands_reason       varchar(40);
alter table public.food_item add column if not exists pregnancy_caution      varchar(60);
alter table public.food_item add column if not exists data_source            varchar(10)  not null default 'recipe';

commit;
