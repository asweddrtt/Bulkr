-- ---------------------------------------------------------------------------
-- Bulkr — the free layer of content moderation
-- ---------------------------------------------------------------------------
-- Run after `feed_schema.sql` and `feed_engagement.sql`. Safe to run more than
-- once.
--
-- App Store guideline 1.2 asks a user-generated-content app for four things: a
-- way to filter objectionable material, a way to report it, a way to block a
-- user, and a contact address. Bulkr already has the middle two —
-- `feed_reports.sql` and `social_privacy.sql`. This is the first one, or the
-- part of it that costs nothing.
--
-- What this is NOT: it is not a classifier and it does not pretend to
-- understand anything. It is an exact-word blocklist, which is the only kind of
-- text filter that is free, instant, and has no dependency to be down. Nudity,
-- harassment, sarcasm and context all need a model, and that arrives beside
-- this rather than instead of it.
--
-- Deliberately short, and it should stay short. A long blocklist is a false
-- positive generator: any list containing "cock" refuses to discuss chicken,
-- and any list matching substrings refuses Scunthorpe. So this holds terms
-- whose every use is abusive, matched as whole words only, and everything
-- arguable is left to the model and to reports.

-- ---------------------------------------------------------------------------
-- 1. The list
-- ---------------------------------------------------------------------------
-- A table rather than a constant in a function, because the answer to "why was
-- my post refused" has to be inspectable, and because adding a term should not
-- mean redeploying anything.
create table if not exists public.banned_terms (
  term text not null,
  -- What it is, for whoever reads this table in a year and wonders. Not shown
  -- to users: telling somebody exactly which word tripped the filter is a
  -- how-to for getting around it.
  note text,
  created_at timestamptz not null default now(),
  constraint banned_terms_pkey primary key (term),
  -- Lower case, no spaces. The matcher folds case and matches whole words, so
  -- a term with a capital or a trailing space would simply never fire — and a
  -- rule that silently never fires is worse than no rule.
  constraint banned_terms_normalised
    check (term = lower(btrim(term)) and term <> '' and term not like '% %')
);

alter table public.banned_terms enable row level security;

-- No policy at all, which means no client can read it. Deliberate: the list is
-- the filter's only secret, and an app that ships the blocklist ships the
-- workaround.
revoke all on table public.banned_terms from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. The matcher
-- ---------------------------------------------------------------------------
-- Whole words, case-insensitive, and that is the whole design.
--
-- `\m` and `\M` are Postgres's word boundaries. Without them "ass" matches
-- "class", "assist", "passage" and "mass" — and a filter that refuses "mass"
-- in an app about gaining mass would be a very short-lived filter.
create or replace function public.contains_banned_term(p_text text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select b.term
    from public.banned_terms b
   where p_text is not null
     and p_text ~* ('\m' || regexp_replace(b.term, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\M')
   limit 1;
$$;

comment on function public.contains_banned_term(text) is
  'The first banned term appearing as a whole word in the text, or null.';

-- Security definer because the table it reads is readable by nobody. The
-- function returns a term only to a caller who already supplied the text
-- containing it, so it leaks nothing the caller did not already write.
revoke all on function public.contains_banned_term(text) from anon;
grant execute on function public.contains_banned_term(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Refusing at the door
-- ---------------------------------------------------------------------------
-- Rejected on insert rather than hidden after it. The author finds out
-- immediately, in the composer, while the text is still in front of them —
-- which is both kinder and cheaper than a post that appears to work and
-- silently reaches nobody.
--
-- The SQLSTATE is what the app matches on. A message string would work until
-- somebody rewords it; a code is a contract.
create or replace function public.reject_banned_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  hit text;
begin
  hit := public.contains_banned_term(new.content);

  if hit is not null then
    -- No term in the message. The author knows what they typed, and naming the
    -- word that tripped is a hint for evading the next one.
    raise exception 'Bulkr: this cannot be posted as written.'
      using errcode = 'BLKR1',
            hint = 'Reword it and try again.';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_reject_banned_terms on public.posts;
create trigger posts_reject_banned_terms
  before insert or update of content on public.posts
  for each row execute function public.reject_banned_terms();

drop trigger if exists post_comments_reject_banned_terms on public.post_comments;
create trigger post_comments_reject_banned_terms
  before insert or update of content on public.post_comments
  for each row execute function public.reject_banned_terms();

-- ---------------------------------------------------------------------------
-- 4. Seeding
-- ---------------------------------------------------------------------------
-- Slurs only, and only ones with no innocent use. No mild profanity: an app
-- whose users are lifting heavy things will contain swearing, and refusing
-- "shit" would be picking a fight with the vocabulary of the audience rather
-- than protecting anyone.
--
-- Left as a placeholder rather than shipped with a list of slurs in the
-- repository. Add them in the SQL editor:
--
--   insert into public.banned_terms (term, note) values
--     ('<term>', 'racial slur')
--   on conflict (term) do nothing;
--
-- The check constraint enforces lower case and no spaces, so a term that would
-- never have matched is refused at insert instead of sitting there dead.

-- ---------------------------------------------------------------------------
-- 5. Verify
-- ---------------------------------------------------------------------------
--   insert into public.banned_terms (term, note) values ('badword', 'test');
--
--   select public.contains_banned_term('this is a badword');  -- badword
--   select public.contains_banned_term('badwordy things');    -- null
--   select public.contains_banned_term('BadWord!');           -- badword
--
-- Then, as a signed-in user, posting text containing it should fail with
-- SQLSTATE BLKR1 rather than inserting.
--
--   delete from public.banned_terms where term = 'badword';
