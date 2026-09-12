# Bulkr's backend

Everything the app talks to that is not Dart: the tables, the row-level
security policies that are the app's actual security boundary, the triggers and
cron jobs, and the three edge functions.

These files were deleted from the repository in `8b441bf` and restored in full.
They are byte-identical to the versions that were removed.

## Read this before trusting these files

**They are not a complete database.** They create 18 tables and assume five
more already exist:

    users        meals        posts        weight_logs        daily_logs

(along with `system_foods` and `cached_off_foods`, which the food search
reads). Those were created by hand in the Supabase dashboard before this
directory existed, and **they have never been in version control at all.**

So running every file below against an empty project will fail. What is here is
the incremental half of the schema — real, and worth having, but half.

**They are also a point in time.** They describe the database as of
September 2026. Anything changed in the dashboard since then — a policy edited
to fix something, a column added — is live in the project and absent here, and
there is no way to tell from inside this repository which.

### Closing both gaps

One command, run against the live project, produces the authoritative schema:

```sh
supabase link --project-ref <ref>
supabase db dump --schema public         > supabase/schema.sql
supabase db dump --schema public --data-only --table system_foods \
                                         > supabase/seed_system_foods.sql
```

Commit `schema.sql`. From then on it is the source of truth, these files become
the history of how it got there, and the two cannot drift apart silently
because a dump is a diff away from telling you they have.

Until that is done, the live Supabase project is the only complete copy of the
schema that exists.

## Apply order

Each file states its own prerequisites in its header comment; this is those
prerequisites resolved into one order. Every file is written to be re-runnable,
so applying one twice changes nothing the second time.

Run them in the SQL editor (Dashboard → SQL Editor → New query):

| # | File | What it adds |
|---|------|--------------|
| 1 | `meals_policies.sql` | RLS on meals and their ingredients |
| 2 | `feed_schema.sql` | What a post is: labels, images, visibility |
| 3 | `feed_engagement.sql` | Likes, saves, comments, `hot_score` |
| 4 | `feed_follows.sql` | The follow graph |
| 5 | `feed_groups.sql` | Groups and membership |
| 6 | `social_privacy.sql` | Visibility levels, blocking, hidden posts |
| 7 | `chat_schema.sql` | Conversations and messages |
| 8 | `notifications.sql` | The notification table and its triggers |
| 9 | `push_devices.sql` | `device_tokens`, one row per phone |
| 10 | `chat_push.sql` | A push when a message arrives |
| 11 | `chat_read_clock.sql` | Server-side read receipts |
| 12 | `feed_reports.sql` | Reporting a post |
| 13 | `feed_challenges.sql` | Challenges and participants |
| 14 | `feed_profiles.sql` | Public profile reads |
| 15 | `feed_avatars.sql` | Avatar storage and its policies |
| 16 | `image_thumbnails.sql` | The ~640px second copy of every photo |
| 17 | `feed_engagement_rpc.sql` | Engagement counters as one round trip |
| 18 | `groups_policy_fix.sql` | Fixes 42501 when creating a private group |
| 19 | `maintenance_cron.sql` | Scheduled decay of `hot_score`, cleanup |
| 20 | `moderation_terms.sql` | The blocked-term check, raising `BULKR` |
| 21 | `moderation_seed.sql` | The term list, English and Arabic |
| 22 | `push_webhook.sql` | The webhook that calls `send-push` |
| 23 | `system_foods_seed.sql` | Curated whole foods for tier-1 search |
| 24 | `tracker_schema.sql` | The daily log |
| 25 | `tracker_water.sql` | `water_logs` |
| 26 | `tracker_insights.sql` | The insight queries behind the dashboard |
| 27 | `weight_logs_policies.sql` | RLS on `weight_logs` — without it, 42501 |
| 28 | `premium.sql` | `subscriptions`, `is_premium()`, the free tier's numbers |

`image_thumbnails.sql` says "run after every other migration" in its own
header, but `feed_engagement_rpc.sql` reads the columns it adds, so it is
placed before that one here. Both readings are satisfied by this order.

## Edge functions

Deployed separately, with `supabase functions deploy <name>`:

- **`delete-account/`** — the account deletion App Store guideline 5.1.1(v)
  requires. Needs the service role key, which is why it is a function and not
  a policy.
- **`food-search/`** — tier 2 of food search, currently USDA FoodData Central.
  Server-side so the FDC key is not shipped in the app binary. Writes what it
  finds into `cached_off_foods`, so tier 1 gets better as the app is used.
- **`send-push/`** — turns a `notifications` row into an FCM message.

Each has its own README with the environment variables it needs. Those
variables hold real credentials and are correctly kept out of this repository
by `.gitignore` — see `supabase/.env` and `supabase/functions/**/.env` there.

## What the app expects to be true

Referenced from the Dart side, so changing these breaks the client:

- `moderation_terms.sql` raises SQLSTATE `BULKR` for a blocked term, which
  `lib/core/moderation_error.dart` matches on.
- `chat_read_clock.sql` sets `last_seen_at` from the server's `now()` in a
  trigger; `lib/data/push_repository.dart` deliberately does not send it.
- `feed_avatars.sql` §2 governs avatar replacement, per
  `lib/data/user_repository.dart`.
- `feed_follows.sql` explains the follow-graph shape that
  `lib/models/person.dart` is built around.
- `premium.sql` holds the free tier's numbers as `free_*()` functions, and
  `test/plan_limits_test.dart` reads this file and fails when they disagree
  with `lib/core/plan_limits.dart`. It also fails if a write policy is ever
  added to `subscriptions` — a client that can grant itself premium is a
  client that will.
