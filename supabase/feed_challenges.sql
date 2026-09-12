-- Feed, slice 4c: challenges.
--
-- `challenge` has been one of the six labels since slice 1, and it has been
-- only a label the whole time — a tag on a post about a challenge rather than
-- something that runs one. This file gives it the mechanics: a goal, a window,
-- participants, and a leaderboard.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `feed_reports.sql`.

-- ---------------------------------------------------------------------------
-- 1. What a challenge measures
-- ---------------------------------------------------------------------------
-- Weight gained since joining, and the choice deserves stating because it
-- shapes everything below.
--
-- This is a bulking app. The number every user is already tracking is their
-- bodyweight, `weight_logs` already exists, and the onboarding flow already
-- seeds it with a day-one anchor. A challenge measured in kilograms gained
-- therefore needs no new logging from anyone — you join, you keep weighing
-- yourself the way you already were, and the leaderboard follows.
--
-- The alternative metrics all need something the app does not have: calories
-- hit needs a streak concept, workouts completed needs workouts, "consistency"
-- needs a definition. Any of them can be added later — `metric` is a column
-- with a CHECK, so a second value is one ALTER away and no existing row has to
-- change.
--
-- The privacy consequence is handled in section 4, and is the reason the
-- leaderboard is a function rather than a view.

-- ---------------------------------------------------------------------------
-- 2. Challenges
-- ---------------------------------------------------------------------------
-- One challenge per post, hanging off it the way a meal does. The post is the
-- announcement — its author's words, its comments, its likes — and the
-- challenge is the machinery. Keeping them separate means a challenge post is
-- still a post everywhere a post appears, with no special case in the feed.
--
-- `post_id` is UNIQUE rather than the primary key. A challenge has its own
-- identity because `challenge_participants` points at it, and a junction table
-- keyed on a foreign key that is also a primary key is the kind of thing that
-- reads fine until you need to move it.

create table if not exists public.challenges (
  id uuid not null default uuid_generate_v4(),
  post_id uuid not null,
  title text not null,
  -- What counts. See section 1.
  metric text not null default 'weight_gain',
  -- The target, in the metric's units. Kilograms for `weight_gain`, always
  -- metric on the wire like every other weight in this app — the imperial
  -- toggle is a display preference and conversion happens at the edge.
  goal_amount numeric not null,
  starts_at timestamp with time zone not null default now(),
  ends_at timestamp with time zone not null,
  created_by uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint challenges_pkey primary key (id),
  constraint challenges_post_id_key unique (post_id),
  constraint challenges_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint challenges_created_by_fkey
    foreign key (created_by) references public.users(id) on delete cascade,
  constraint challenges_metric_check check (metric in ('weight_gain')),
  constraint challenges_title_check
    check (char_length(btrim(title)) between 3 and 80),
  -- A goal of zero is not a challenge, and a negative one is a cut — which
  -- this app does not do and whose leaderboard would sort the wrong way.
  constraint challenges_goal_check check (goal_amount > 0),
  -- A window that ends before it starts has no meaning, and every "is it
  -- running" check would have to guess what was intended.
  constraint challenges_window_check check (ends_at > starts_at)
);

-- CASCADE from the post, unlike the attached meal's SET NULL. The difference
-- is what the row is: a meal exists independently of the post that mentions
-- it, so the post going away leaves the meal alone. A challenge exists only
-- as this post's challenge — there is no other way to reach it — so deleting
-- the announcement deletes the challenge, and its participants with it.

-- ---------------------------------------------------------------------------
-- 3. Participants
-- ---------------------------------------------------------------------------
-- The pair is the primary key, so joining twice is refused by the key.
--
-- `start_weight_kg` is a snapshot taken at join time, and it is the whole
-- reason the leaderboard is computable at all. The alternative — asking
-- "what did this person weigh on the day they joined" — is a query against
-- `weight_logs`, which is owner-only, so nobody could run it for anyone else.
-- A snapshot turns the question into arithmetic on two numbers.
--
-- Nullable, and deliberately so: someone who has never logged a weight can
-- still join. They simply have no standing until they log one, which the
-- leaderboard reports as "no data" rather than as zero — zero would put them
-- ahead of everyone who has lost weight and behind everyone who has gained,
-- which is a position they have not earned either way.

create table if not exists public.challenge_participants (
  challenge_id uuid not null,
  user_id uuid not null,
  start_weight_kg numeric,
  joined_at timestamp with time zone not null default now(),
  constraint challenge_participants_pkey primary key (challenge_id, user_id),
  constraint challenge_participants_challenge_id_fkey
    foreign key (challenge_id) references public.challenges(id)
      on delete cascade,
  constraint challenge_participants_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- 4. The leaderboard
-- ---------------------------------------------------------------------------
-- This is the interesting part of the file.
--
-- A leaderboard needs every participant's progress. Progress is
-- `users.current_weight_kg - challenge_participants.start_weight_kg`, and
-- both halves are a problem to expose:
--
--   * `start_weight_kg` sits on a row about another person. If that row were
--     readable, joining a challenge would publish what you weighed on the day
--     you joined — to everyone, forever.
--   * `users.current_weight_kg` is readable today only because
--     `feed_follows.sql` section 6 opened up `users`, which that file flags as
--     a hole to close. This function must keep working after it is closed.
--
-- So the leaderboard is a SECURITY DEFINER function that reads both and
-- returns neither. It emits the delta and nothing else: a number that says "up
-- 2.4 kg", which is what a participant consented to show by joining, and from
-- which nobody can work out what anyone weighs.
--
-- `search_path` is pinned, as it must be on any definer function: without it
-- the caller's path decides which `users` this resolves to.
--
-- The only argument is the challenge id, and the only rows it can reach are
-- that challenge's participants — the caller has no way to widen it.

create or replace function public.challenge_leaderboard(challenge uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  gained_kg numeric,
  joined_at timestamp with time zone,
  has_data boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.user_id,
    u.username::text,
    u.display_name::text,
    u.avatar_url,
    -- Rounded to one decimal on the way out. A leaderboard reporting
    -- 2.3999999 kg is a leaderboard nobody trusts, and the extra precision is
    -- noise from a scale that reads to 0.1 at best.
    case
      when p.start_weight_kg is null or u.current_weight_kg is null then null
      else round(u.current_weight_kg - p.start_weight_kg, 1)
    end as gained_kg,
    p.joined_at,
    (p.start_weight_kg is not null and u.current_weight_kg is not null)
      as has_data
  from public.challenge_participants p
  join public.users u on u.id = p.user_id
 where p.challenge_id = challenge
 -- Most gained first. NULLS LAST puts the participants with no weight logged
 -- at the bottom, which is where "no data" belongs — not at the top, which is
 -- where a descending sort would otherwise put them.
 order by gained_kg desc nulls last, p.joined_at asc;
$$;

-- Only signed-in users may call it. `public` and `anon` are excluded, so the
-- function is not a way around the read policies for someone with only the
-- publishable key and no session.
revoke all on function public.challenge_leaderboard(uuid) from public;
grant execute on function public.challenge_leaderboard(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Joining takes the snapshot
-- ---------------------------------------------------------------------------
-- The client could send `start_weight_kg` itself, and then a client could send
-- any number it liked — starting a challenge at 40 kg makes a very good
-- leaderboard position. So the column is filled in by a trigger from
-- `users.current_weight_kg`, and whatever the insert supplied is discarded.
--
-- SECURITY DEFINER because it reads the joining user's own `users` row, which
-- their own policy allows — but making it definer means the trigger keeps
-- working if `users` reads are narrowed later, which `feed_follows.sql`
-- section 6 says they should be.

create or replace function public.challenge_participants_snapshot_weight()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select u.current_weight_kg into new.start_weight_kg
    from public.users u
   where u.id = new.user_id;

  return new;
end;
$$;

drop trigger if exists challenge_participants_snapshot_trigger
  on public.challenge_participants;
create trigger challenge_participants_snapshot_trigger
  before insert on public.challenge_participants
  for each row execute function public.challenge_participants_snapshot_weight();

-- ---------------------------------------------------------------------------
-- 6. Row level security
-- ---------------------------------------------------------------------------

alter table public.challenges             enable row level security;
alter table public.challenge_participants enable row level security;

-- A challenge is as visible as the post announcing it. Rather than restating
-- the posts policy — which now has a group clause and will grow again — this
-- defers to it: if you can select the post, you can select its challenge.
drop policy if exists "Challenges follow their post" on public.challenges;
create policy "Challenges follow their post"
  on public.challenges for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));

-- Only the post's author can attach a challenge to it, and only as themselves.
-- Both halves matter: the first stops someone bolting a challenge onto another
-- person's post, the second stops them crediting it to somebody else.
drop policy if exists "Challenges are creatable by the post's author"
  on public.challenges;
create policy "Challenges are creatable by the post's author"
  on public.challenges for insert to authenticated
  with check (
    auth.uid() = created_by
    and exists (
      select 1 from public.posts p
       where p.id = post_id and p.user_id = auth.uid()
    )
  );

drop policy if exists "Challenges are editable by their creator" on public.challenges;
create policy "Challenges are editable by their creator"
  on public.challenges for update to authenticated
  using (auth.uid() = created_by)
  with check (auth.uid() = created_by);

drop policy if exists "Challenges are deletable by their creator" on public.challenges;
create policy "Challenges are deletable by their creator"
  on public.challenges for delete to authenticated
  using (auth.uid() = created_by);

-- Participation rows are NOT publicly readable, and this is the pair to
-- section 4. Each participant sees their own row — which is how the app knows
-- whether the Join button should say "joined" — and nobody sees anyone else's,
-- because the row carries a start weight.
--
-- The leaderboard is how everyone else learns who is participating, and it
-- returns deltas rather than weights. That is the whole design: the table
-- holds the sensitive number, the function publishes the harmless one.
drop policy if exists "Participation is readable by the participant"
  on public.challenge_participants;
create policy "Participation is readable by the participant"
  on public.challenge_participants for select to authenticated
  using (auth.uid() = user_id);

-- Joining. Only as yourself, only a challenge you can see, and only while it
-- is running — joining a challenge that ended last month would put someone on
-- a leaderboard for a window they were not in.
drop policy if exists "Users join challenges as themselves"
  on public.challenge_participants;
create policy "Users join challenges as themselves"
  on public.challenge_participants for insert to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.challenges c
       where c.id = challenge_id
         and now() < c.ends_at
         and exists (select 1 from public.posts p where p.id = c.post_id)
    )
  );

-- Leaving. Deletes the snapshot with it, so re-joining later starts from
-- wherever the user is then rather than from where they were the first time.
drop policy if exists "Users leave challenges" on public.challenge_participants;
create policy "Users leave challenges"
  on public.challenge_participants for delete to authenticated
  using (auth.uid() = user_id);

-- No UPDATE policy. The only mutable column is the snapshot, and letting a
-- participant write it is exactly what section 5 exists to prevent.

-- ---------------------------------------------------------------------------
-- 7. Indexes
-- ---------------------------------------------------------------------------

-- A post's challenge. The unique constraint on `post_id` already provides
-- this index, so there is nothing to add — noted so the absence does not read
-- as an oversight.

-- The leaderboard, and "who is in this challenge". The primary key
-- `(challenge_id, user_id)` serves both as a prefix match.

-- "Which challenges am I in" — the other direction, which the primary key
-- cannot serve.
create index if not exists challenge_participants_user_id_joined_at_idx
  on public.challenge_participants (user_id, joined_at desc);

-- Challenges still running, soonest to end first: the natural order for a
-- "live challenges" list, and the filter that list is built on.
create index if not exists challenges_ends_at_idx
  on public.challenges (ends_at desc);

-- ---------------------------------------------------------------------------
-- 8. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- Two new tables, a new unique constraint, and a new RPC. Until PostgREST
-- re-reads them, `/rest/v1/rpc/challenge_leaderboard` is a 404 and the
-- `challenges!challenges_post_id_fkey` embed answers PGRST200.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That the snapshot is taken by the server and not by the client. Insert with
-- a deliberately wrong start weight and check what was stored:
--   insert into public.challenge_participants
--          (challenge_id, user_id, start_weight_kg)
--   values ('<challenge>', auth.uid(), 1);
--   select start_weight_kg from public.challenge_participants
--    where challenge_id = '<challenge>' and user_id = auth.uid();
--   -- expect your real current_weight_kg, not 1
--
-- That you cannot read anyone else's participation row. As a user in a
-- challenge with other people, this must return exactly one row — yours:
--   select * from public.challenge_participants
--    where challenge_id = '<challenge>';
--
-- That the leaderboard nonetheless shows everyone, without their weights:
--   select * from public.challenge_leaderboard('<challenge>');
--
-- That a finished challenge cannot be joined. Against a challenge whose
-- `ends_at` has passed, this must be refused by RLS (42501):
--   insert into public.challenge_participants (challenge_id, user_id)
--   values ('<finished-challenge>', auth.uid());
--
-- That you cannot attach a challenge to someone else's post — refused (42501):
--   insert into public.challenges (post_id, title, goal_amount, ends_at,
--                                  created_by)
--   select id, 'Nice try', 5, now() + interval '30 days', auth.uid()
--     from public.posts where user_id <> auth.uid() limit 1;
--
-- And that the function is not reachable without a session. With the
-- publishable key and no Authorization header, this must be denied:
--   POST /rest/v1/rpc/challenge_leaderboard  {"challenge": "<uuid>"}
