-- Feed, slice 4b: reporting a post.
--
-- `feed_schema.sql` added `posts.report_count` and said what it was for, and
-- since then the app has been telling anyone who tapped Report that the
-- feature was not available — which was true. This file makes it true no
-- longer.
--
-- The thing this file is really about is section 3. A reports table that only
-- ever accumulates rows nobody reads is moderation theatre: it makes the app
-- look like it takes abuse seriously while doing nothing about it. There is no
-- admin panel here and no moderator, so the threshold is the moderator.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `feed_groups.sql`.

-- ---------------------------------------------------------------------------
-- 1. Reports
-- ---------------------------------------------------------------------------
-- One row per person per post. The pair is the primary key, which caps each
-- account at one report per post — without it, one angry user could hide
-- anything by reporting it five times.
--
-- `reason` is a fixed set rather than free text. Free text invites abuse of
-- the report form itself, cannot be counted, and would need reading by
-- someone. A short enumeration is sortable and says enough to act on.
--
-- `note` is the escape hatch, optional and bounded, for the case the
-- enumeration does not cover. It is stored and never shown to anyone but the
-- reporter.

create table if not exists public.post_reports (
  post_id uuid not null,
  reporter_id uuid not null,
  reason text not null,
  note text,
  created_at timestamp with time zone not null default now(),
  constraint post_reports_pkey primary key (post_id, reporter_id),
  constraint post_reports_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint post_reports_reporter_id_fkey
    foreign key (reporter_id) references public.users(id) on delete cascade,
  constraint post_reports_reason_check
    check (reason in ('spam', 'harassment', 'misinformation',
                      'inappropriate', 'other')),
  constraint post_reports_note_check
    check (note is null or char_length(note) <= 500)
);

-- ---------------------------------------------------------------------------
-- 2. The counter
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER, for the same reason the like counter is: the column lives
-- on somebody else's post row, and the posts UPDATE policy only lets an author
-- touch their own. A trigger running as the reporter would be refused by RLS
-- on every report of anyone else's post — which is every report anyone makes.

-- The hide threshold, defined before the trigger that calls it. A function
-- rather than a literal so it appears in one place and can be changed without
-- editing a trigger body. See section 3 for why it is three.
create or replace function public.post_report_hide_threshold()
returns integer
language sql
immutable
as $$ select 3 $$;

create or replace function public.post_reports_sync_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reports integer;
begin
  -- Counted rather than incremented. The like counters increment because they
  -- move constantly and a count(*) per like would be wasteful; reports are
  -- rare, and the threshold below is a decision worth making from the real
  -- number rather than from a running total that may have drifted.
  select count(*) into reports
    from public.post_reports
   where post_id = coalesce(new.post_id, old.post_id);

  update public.posts
     set report_count = reports,
         -- See section 3. Only ever set true here, never false: clearing a
         -- report-driven hide is a decision a person makes, and this trigger
         -- is not a person.
         is_hidden = is_hidden or reports >= public.post_report_hide_threshold()
   where id = coalesce(new.post_id, old.post_id);

  return null;
end;
$$;

drop trigger if exists post_reports_count_trigger on public.post_reports;
create trigger post_reports_count_trigger
  after insert or delete on public.post_reports
  for each row execute function public.post_reports_sync_count();

-- ---------------------------------------------------------------------------
-- 3. Auto-hide, and why
-- ---------------------------------------------------------------------------
-- There is no admin panel, no moderator queue and nobody whose job it is to
-- read reports. Given that, there are exactly two honest designs:
--
--   (a) Do not offer reporting at all, and say so.
--   (b) Let reports do something by themselves.
--
-- (a) was the state of the app until this file, and it was defensible. It
-- stops being defensible the moment there are enough users for one of them to
-- post something that needs taking down at 3am.
--
-- So: three distinct accounts reporting a post takes it off the feed. Not one
-- — that hands every user a veto over every post. Three is low enough to act
-- within minutes on a small app and high enough that it takes coordination to
-- abuse.
--
-- What auto-hide is NOT: a punishment, or a deletion. The post survives, its
-- author still sees it on their own profile with the hidden marker, and
-- un-hiding is a single UPDATE — which the author themselves can do, because
-- `is_hidden` is in their column grant.
--
-- That last part is a real hole and worth naming: a determined author can
-- un-hide a post the community hid. Closing it means taking `is_hidden` out of
-- the author's grant and giving them a separate "unpublish" column, so that
-- author-hidden and report-hidden are different states. That is the right
-- design and it is not this file — because with three users, an author who
-- un-hides their reported post is a conversation, not a security problem.
--
-- The threshold itself is defined at the top of section 2, before the trigger
-- that calls it.

-- ---------------------------------------------------------------------------
-- 4. Row level security
-- ---------------------------------------------------------------------------

alter table public.post_reports enable row level security;

-- A reporter sees their own reports and nobody else's. Not even the post's
-- author — especially not the post's author. Knowing who reported you is the
-- beginning of retaliating for it, and the whole value of a report is that it
-- can be made without that risk.
--
-- The consequence is that nobody can read the report queue through the API at
-- all, including whoever runs the app. That is intentional: use the Supabase
-- dashboard, which runs as the service role and is not subject to RLS. An
-- app-visible moderation queue needs a role to show it to, and there isn't one.
drop policy if exists "Reports are readable by their reporter" on public.post_reports;
create policy "Reports are readable by their reporter"
  on public.post_reports for select to authenticated
  using (auth.uid() = reporter_id);

-- Reporting. Only as yourself, and not your own post — reporting yourself is
-- either a mistake or an attempt to test the threshold, and neither needs
-- supporting.
drop policy if exists "Users report as themselves" on public.post_reports;
create policy "Users report as themselves"
  on public.post_reports for insert to authenticated
  with check (
    auth.uid() = reporter_id
    and not exists (
      select 1 from public.posts p
       where p.id = post_id and p.user_id = auth.uid()
    )
  );

-- Withdrawing a report. The count and the hide are recomputed by the trigger,
-- but the hide is never lifted by it — see section 3.
drop policy if exists "Users withdraw their own reports" on public.post_reports;
create policy "Users withdraw their own reports"
  on public.post_reports for delete to authenticated
  using (auth.uid() = reporter_id);

-- No UPDATE policy. Changing the reason on a report is a withdraw and a new
-- report, and modelling it as one operation would let a reporter rewrite
-- history on a post that has already been hidden.

-- ---------------------------------------------------------------------------
-- 5. Indexes
-- ---------------------------------------------------------------------------
-- The primary key `(post_id, reporter_id)` already serves the count and the
-- "have I reported this" check.

-- "Everything I have reported", for marking those posts in the feed.
create index if not exists post_reports_reporter_id_created_at_idx
  on public.post_reports (reporter_id, created_at desc);

-- The moderation view, for whoever is looking at this in the dashboard:
-- most-reported first, and only posts with reports on them.
create index if not exists posts_report_count_idx
  on public.posts (report_count desc) where report_count > 0;

-- ---------------------------------------------------------------------------
-- 6. Backfill
-- ---------------------------------------------------------------------------
-- For a database that already has report rows from a previous run. Guarded to
-- rows that disagree, so a re-run is a no-op.

update public.posts p
   set report_count = counted.reports
  from (
    select p2.id,
           (select count(*) from public.post_reports r where r.post_id = p2.id)
             as reports
      from public.posts p2
  ) counted
 where counted.id = p.id and p.report_count <> counted.reports;

-- ---------------------------------------------------------------------------
-- 7. Reload the API's schema cache
-- ---------------------------------------------------------------------------

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That you cannot report your own post. This must be refused by RLS (42501):
--   insert into public.post_reports (post_id, reporter_id, reason)
--   select id, auth.uid(), 'spam' from public.posts
--    where user_id = auth.uid() limit 1;
--
-- That reporting twice is refused rather than counted twice — the second must
-- raise a unique violation (23505):
--   -- insert the same (post_id, reporter_id) pair twice
--
-- That the threshold hides. As three different accounts, report one post, then
-- check as its author:
--   select id, report_count, is_hidden from public.posts where id = '<post>';
--
-- That the counter matches what it counts — no rows means no drift:
--   select p.id, p.report_count
--     from public.posts p
--    where p.report_count <>
--          (select count(*) from public.post_reports r where r.post_id = p.id);
--
-- The moderation queue, from the dashboard (service role, not the app):
--   select p.id, p.report_count, p.is_hidden, u.username, p.content,
--          (select array_agg(distinct r.reason)
--             from public.post_reports r where r.post_id = p.id) as reasons
--     from public.posts p
--     join public.users u on u.id = p.user_id
--    where p.report_count > 0
--    order by p.report_count desc;
--
-- To clear a report-driven hide after reviewing it, from the dashboard:
--   update public.posts set is_hidden = false where id = '<post>';
--   delete from public.post_reports where post_id = '<post>';
--   -- in that order: the delete re-runs the trigger, which will not re-hide
--   -- a post whose report count is now below the threshold.
