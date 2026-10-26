-- PROPOSED, NOT APPLIED. Kept out of supabase/migrations/ so `supabase db push` cannot run it by accident.
-- Needs review and OK from Elwin and Jun Ting; then move it to migrations/ (PROJECT_STATE §11).
--
-- chat_report: a patient's report that a chatbot answer was wrong or unhelpful (Elwin, 11 Oct,
-- "Report this answer" under each reply). Saved as NEW; a reviewer reads it in the chat backlog
-- (ai_server/chat_backlog.py), checks it, and adds a rule or new wording to the knowledge base
-- (status ADDED) or not (REJECTED). Nothing in the knowledge base changes on its own.
-- Not in the report's ERD (Chapter 4); app side: ChatReport, ITreatmentRepository.saveChatReport.
--
-- Until this is applied the app's insert fails and the sheet shows "The report could not be
-- sent. Please try again later."; the chat itself is unaffected.

create table public.chat_report (
  report_id           uuid primary key default gen_random_uuid(),
  account_id          uuid         not null references public.account (account_id) on delete cascade,
  -- The stored chat_message rows, when the app saved them; the texts below are kept either way.
  question_message_id uuid         references public.chat_message (message_id) on delete set null,
  answer_message_id   uuid         references public.chat_message (message_id) on delete set null,
  question_text       text         not null check (char_length(question_text) between 1 and 1000),
  answer_text         text         not null,
  answer_category     varchar(50),           -- the rule the chatbot matched
  matched_by          varchar(30),           -- red_flag | category | keyword | similar_question | ...
  expected_text       text         check (expected_text is null or char_length(expected_text) <= 500),
  wanted_category     varchar(50),           -- the topic the patient says they meant
  status              varchar(10)  not null default 'NEW'
                      check (status in ('NEW', 'REVIEWED', 'ADDED', 'REJECTED')),
  reviewed_note       text,                  -- reviewer's note (what was added, or why not)
  created_at          timestamptz  not null default now()
);

-- Foreign keys are indexed (joins, ON DELETE); the reviewer reads the NEW ones oldest first.
create index chat_report_account_idx  on public.chat_report (account_id, created_at);
create index chat_report_question_idx on public.chat_report (question_message_id);
create index chat_report_answer_idx   on public.chat_report (answer_message_id);
create index chat_report_new_idx      on public.chat_report (created_at) where status = 'NEW';

-- RLS: a patient can file reports and read their own, nothing else. Only NEW rows can be inserted;
-- the status is changed by the reviewer with the service role (dashboard), so no update or delete
-- policy for patients.
alter table public.chat_report enable row level security;
grant select, insert on table public.chat_report to authenticated;
grant select, insert, update, delete on table public.chat_report to service_role;

create policy "owner reads chat_report" on public.chat_report for select to authenticated
  using ((select auth.uid()) = account_id);
create policy "owner inserts chat_report" on public.chat_report for insert to authenticated
  with check ((select auth.uid()) = account_id and status = 'NEW' and reviewed_note is null);

-- Reviewer's export for chat_backlog.py (run in the SQL editor, save as CSV):
--   select r.report_id, r.created_at, r.question_text, r.answer_category, r.matched_by,
--          r.expected_text, r.wanted_category, r.answer_text
--   from public.chat_report r
--   where r.status = 'NEW'
--   order by r.created_at;
