-- ---------------------------------------------------------------------------
-- Bulkr — hate-term seed, English and Arabic
-- ---------------------------------------------------------------------------
-- Run after `moderation_terms.sql`. Safe to run more than once.
--
-- Two jobs: teach the matcher how Arabic is actually written, and fill the list
-- that shipped empty.
--
-- The scope is hate, not swearing. Bulkr's users are lifting heavy things and
-- will say so; "this is fucking great" is a compliment and refusing it would be
-- picking a fight with the vocabulary of the audience. What is refused is
-- abuse aimed at what somebody is — race, religion, sexuality, disability.

-- ---------------------------------------------------------------------------
-- 1. Folding the ways one word can be spelled
-- ---------------------------------------------------------------------------
-- Arabic makes the plain matcher useless on its own, in two ways.
--
-- Short vowels are optional in writing, so خَوَل and خول are the same word and
-- the diacritics are free evasion. So is the tatweel, the decorative stretch in
-- خــول. And several letters are written more than one way: the alef family
-- (أ إ آ ٱ), yeh against alef-maqsura (ي / ى), teh-marbuta against heh
-- (ة / ه). Enumerating the combinations is not possible; normalising them is
-- one function.
--
-- Arabic-Indic digits fold too, because Arabizi — Arabic typed in Latin
-- letters, which is how most people in Egypt actually type — substitutes
-- numerals for letters, and ٣ and 3 should not be two different rules.
create or replace function public.normalize_for_matching(p_text text)
returns text
language sql
immutable
as $$
  select lower(
    translate(
      translate(
        coalesce(p_text, ''),
        -- Tashkeel and the tatweel, deleted: `translate` drops any character
        -- in `from` that has no partner in `to`.
        --
        -- Written as U& escapes rather than as the characters themselves, and
        -- that is not fussiness. The first version of this used a regexp
        -- character class typed literally, which came out of its own file
        -- spanning U+0610 to U+064B — a range that contains every Arabic
        -- letter. `normalize_for_matching('كتاب')` returned the empty string
        -- and the whole Arabic half of the list silently matched nothing.
        -- Combining marks do not survive being typed into a file; codepoints
        -- do.
        --
        -- 064B-0652 fathatan..sukun, 0653-0656 maddah and the hamzas,
        -- 0670 superscript alef, 0640 tatweel.
        U&'\064B\064C\064D\064E\064F\0650\0651\0652\0653\0654\0655\0656\0670\0640',
        ''
      ),
      -- One-to-one folds. Alef family -> bare alef, alef-maqsura -> yeh,
      -- teh-marbuta -> heh, hamza carriers -> their base letter, and the
      -- Arabic-Indic digits -> ASCII, because Arabizi swaps numerals for
      -- letters and ٣ and 3 must not be two rules.
      U&'\0623\0625\0622\0671\0649\0629\0624\0626\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669',
      U&'\0627\0627\0627\0627\064A\0647\0648\064A0123456789'
    )
  );
$$;

comment on function public.normalize_for_matching(text) is
  'Case-folded, with Arabic diacritics stripped and letter variants unified.';

-- ---------------------------------------------------------------------------
-- 2. The matcher, taught about Arabic morphology
-- ---------------------------------------------------------------------------
-- Whole-word matching nearly fails in Arabic, and the reason is grammatical.
-- The definite article ال attaches directly to the noun, as do the conjunction
-- و and the prepositions ب ل ك ف — so الخول is the ordinary way to write the
-- word, and `\mخول\M` does not match it. Measured, not assumed: on a real
-- Postgres, `'الخول' ~ '\mخول\M'` is false.
--
-- So the pattern allows an optional proclitic cluster. The letters are Arabic,
-- which is why the same pattern is harmless in front of an English term.
--
-- The closing `\M` stays. Dropping it to catch suffixes would also match a
-- term inside an unrelated longer word — خولاني is a surname — and a filter
-- that refuses somebody's name is worse than one that misses a plural. Plurals
-- worth catching are listed as their own rows instead.
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
     and public.normalize_for_matching(p_text) ~
         ('\m(وال|فال|بال|كال|ال|و|ف|ب|ل|ك)?'
          || regexp_replace(b.term, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
          || '\M')
   limit 1;
$$;

revoke all on function public.contains_banned_term(text) from anon;
grant execute on function public.contains_banned_term(text) to authenticated;

-- Terms are stored already folded, so a row can never be written that the
-- matcher would then look for in a form it never sees. Replaces the plainer
-- lower/btrim check from `moderation_terms.sql`.
alter table public.banned_terms
  drop constraint if exists banned_terms_normalised;

alter table public.banned_terms
  add constraint banned_terms_normalised
  check (
    term = public.normalize_for_matching(btrim(term))
    and term <> ''
    and term not like '% %'
  );

-- ---------------------------------------------------------------------------
-- 3. English
-- ---------------------------------------------------------------------------
-- Terms with no non-abusive use. Plurals listed where the singular's `\M`
-- would miss them.
insert into public.banned_terms (term, note) values
  ('nigger', 'racial slur'),
  ('niggers', 'racial slur'),
  ('coon', 'racial slur'),
  ('coons', 'racial slur'),
  ('darkie', 'racial slur'),
  ('darky', 'racial slur'),
  ('negress', 'racial slur'),
  ('chink', 'racial slur'),
  ('chinks', 'racial slur'),
  ('gook', 'racial slur'),
  ('gooks', 'racial slur'),
  ('spic', 'ethnic slur'),
  ('spics', 'ethnic slur'),
  ('beaner', 'ethnic slur'),
  ('wetback', 'ethnic slur'),
  ('wetbacks', 'ethnic slur'),
  ('kike', 'antisemitic slur'),
  ('kikes', 'antisemitic slur'),
  ('paki', 'ethnic slur'),
  ('pakis', 'ethnic slur'),
  ('towelhead', 'anti-Arab slur'),
  ('towelheads', 'anti-Arab slur'),
  ('raghead', 'anti-Arab slur'),
  ('ragheads', 'anti-Arab slur'),
  ('sandnigger', 'anti-Arab slur'),
  ('mudslime', 'anti-Muslim slur'),
  ('muzzie', 'anti-Muslim slur'),
  ('muzzies', 'anti-Muslim slur'),
  ('squaw', 'anti-Indigenous slur'),
  ('injun', 'anti-Indigenous slur'),
  ('faggot', 'anti-gay slur'),
  ('faggots', 'anti-gay slur'),
  ('tranny', 'anti-trans slur'),
  ('trannies', 'anti-trans slur'),
  ('shemale', 'anti-trans slur'),
  ('retard', 'ableist slur'),
  ('retards', 'ableist slur'),
  ('retarded', 'ableist slur'),
  ('mongoloid', 'ableist slur')
on conflict (term) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Arabic and Arabizi
-- ---------------------------------------------------------------------------
-- Sectarian and anti-gay abuse, in script and in the Latin spellings people
-- actually type. Stored folded: شرموطة normalises to شرموطه, so that is the
-- form on the row.
insert into public.banned_terms (term, note) values
  ('خول', 'anti-gay slur'),
  ('خولات', 'anti-gay slur, plural'),
  ('khawal', 'anti-gay slur, Arabizi'),
  ('khawals', 'anti-gay slur, Arabizi'),
  ('منيوك', 'anti-gay slur'),
  ('متناك', 'anti-gay slur'),
  ('metnak', 'anti-gay slur, Arabizi'),
  ('رافضي', 'anti-Shia sectarian slur'),
  ('روافض', 'anti-Shia sectarian slur'),
  ('rafidi', 'anti-Shia sectarian slur, Arabizi'),
  ('مجوسي', 'anti-Shia sectarian slur'),
  ('مجوس', 'anti-Shia sectarian slur'),
  ('majusi', 'anti-Shia sectarian slur, Arabizi')
on conflict (term) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Deliberately NOT on the list
-- ---------------------------------------------------------------------------
-- Each of these was considered and rejected. Worth writing down, because every
-- one of them is a plausible-looking addition that would break something.
--
--   عبد        "slave", and the anti-Black use is real — but it is also the
--              first half of عبد الله, عبد الرحمن, عبد العزيز. Measured on a
--              real Postgres: with this term on the list, "عبد الله محمود"
--              matches. It would refuse a man named Abdullah from writing his
--              own name.
--   يهودي      "Jewish". A description, not a slur.
--   كافر       a theological term with a large legitimate literature. Used as
--              abuse, but not only as abuse.
--   نجس        "impure" — appears in ordinary religious rulings about washing.
--   صليبي      "crusader": history as often as abuse.
--   nigga      in-group use and song lyrics are most of its occurrences.
--              Blocking it mostly refuses Black users quoting music.
--   fag        a cigarette in British English.
--   dyke       a water barrier, and a surname.
--   homo       a prefix, and half of "homo sapiens".
--   spastic    a clinical term as well as a British playground slur.
--   cripple    a verb in ordinary use.
--
-- If any of these matter for your users, add them and then test with real
-- sentences your users would write. `contains_banned_term` is the whole test.

-- ---------------------------------------------------------------------------
-- 6. Severe sexual abuse
-- ---------------------------------------------------------------------------
-- Not protected-class hate: sexual and misogynistic insults, enabled on the
-- owner's decision after being shown the trade.
--
-- Worth knowing what that trade is, because it is the one place this list
-- reaches past hate into ordinary rudeness. Several of these are everyday
-- profanity in Egyptian Arabic — closer in register to "bastard" than to a
-- slur — and unlike the terms in sections 3 and 4 they will be typed by people
-- with no intention of abusing anyone in particular. Expect them to fire more
-- often than everything above combined.
--
-- Removing any of them is one delete and needs no build:
--
--   delete from public.banned_terms where term = '<term>';
insert into public.banned_terms (term, note) values
  ('شرموطه', 'sexual slur'),
  ('شراميط', 'sexual slur, plural'),
  ('sharmouta', 'sexual slur, Arabizi'),
  ('sharmoota', 'sexual slur, Arabizi'),
  ('قحبه', 'sexual slur'),
  ('gahba', 'sexual slur, Arabizi'),
  ('qahba', 'sexual slur, Arabizi'),
  ('عرص', 'sexual slur'),
  ('3ars', 'sexual slur, Arabizi')
on conflict (term) do nothing;

-- ---------------------------------------------------------------------------
-- 7. Verify
-- ---------------------------------------------------------------------------
--   select count(*) from public.banned_terms;
--
-- Then check both that it catches and that it does not over-catch:
--
--   select public.contains_banned_term('هذا الخول');        -- خول
--   select public.contains_banned_term('يا خَوَل');          -- خول
--   select public.contains_banned_term('عبد الله محمود');   -- null
--   select public.contains_banned_term('gaining mass');     -- null
--   select public.contains_banned_term('this is fucking great');  -- null
