# Free and premium

**Decided:** Option A below — free keeps every feature and screen, and cannot
accumulate. **$6.99/month or $39.99/year**, yearly shown first.

| | Free | Premium |
|---|---|---|
| Logging, food search, tracker, feed, DMs | unlimited | unlimited |
| Saved meal library | 20 | unlimited |
| Tracker history | last 7 days | all of it |
| Weekly recap | current week | every week |
| Active challenges | 1 | unlimited |
| Insights, trends, projections | all of them | all of them |
| Ads | banner + interstitial | none |

Store products, to be created in App Store Connect and Play Console:

| Product id | Price | Notes |
|---|---|---|
| `bulkr_premium_monthly` | $6.99 / month | exists mostly to make the yearly look cheap |
| `bulkr_premium_yearly` | $39.99 / year | ~$3.33/mo, 52% off. Show first, default to it. |

**7-day free trial on the yearly.** Configured as an introductory offer in the
store, not in app code — App Store Connect calls it a *free* introductory
offer, Play Console a *free trial* on the base plan. Do not build a trial into
Bulkr: a home-grown one is a date the client can move, and both stores handle
eligibility, one-per-account, and the cancel-before-renewal flow that Apple
requires you not to reimplement.

Three things follow from having one:

- **Eligibility is the store's answer, not ours.** Somebody who already used
  the trial sees the plain price. The upgrade screen has to read the offer off
  the product rather than hardcode "7 days free", or it will promise a trial
  to people who cannot have one — which is a guideline 2.3.1 problem as well
  as a lie.
- **The screen must say what happens on day 8.** "Free for 7 days, then
  $39.99/year. Cancel any time." Both stores require the full terms next to
  the button, and it is also the thing that stops the refund request.
- **The first charge lands a week after the excitement wears off.** That is
  where refunds come from, and it is the cost of the higher conversion. Worth
  watching `upgrade_completed` against cancellations once there are enough
  subscribers to measure.

The rest of this file is the tour behind those numbers: everything the app
does, which side of the line each thing could sit on, and the two splits that
were considered and not taken — because the split is a pricing decision, not
an engineering one, and it is the part that is expensive to change later.

The mechanism is already built and is deliberately separate from the policy:

| Where | What it holds |
|---|---|
| `lib/core/plan_limits.dart` | every number, in one file |
| `supabase/premium.sql` | the same numbers, where they are enforced |
| `lib/models/entitlement.dart` | what the client is and is not trusted with |
| `lib/cubit/entitlement/` | one app-wide answer to "is this account premium" |

Changing the split is editing `PlanLimits.free`, editing the matching
`free_*()` function in `premium.sql`, and re-running it. `plan_limits_test.dart`
fails if only one of the two is changed.

---

## The tour

Everything Bulkr does today, and what it costs us to serve.

### The core loop — never gate any of this

| Feature | Why it stays free |
|---|---|
| Logging meals and food, any number, any day | The thing the app is for. Someone who cannot record dinner does not come back, and no upgrade screen wins that user back. |
| Food search (3 tiers, barcode scanning) | Tier 2 costs an API call, but a search you cannot run is a meal you cannot log. |
| The daily tracker, calorie ring, macro bars | Same. |
| Water logging | Same. |
| Weighing in | Same. |
| Onboarding, the calculated plan, recalculating it | The value has to land before the ask does. |
| The feed, posting, comments, likes, follows, DMs | A social network with a paywall on posting has no network. Ads are how the free tier pays for itself here. |

This is most of the app, and that is the point. A free tier that is genuinely
useful forever is what makes $7 a decision about convenience rather than a
ransom.

### What can carry a limit

| Feature | Server cost | Gate-ability | Notes |
|---|---|---|---|
| Saved meal library | storage, tiny | **high** | The clearest one. It only fills up for someone already using the app weekly, which is exactly who converts. |
| Tracker history depth | none, it is already stored | **high** | Cheap to serve, valuable to look at. The classic fitness-app paywall. |
| Weekly recap | one RPC | medium | Free gets the current week; going back is premium. |
| Insights / dashboard trend cards | pure computation | medium | "Less analytics" — see the options below. |
| Weight projections, pace, BMI, charts | pure computation | medium | Same family. |
| Challenges | rows | medium | One at a time on free is a real limit that costs nobody anything. |
| Groups you can create | rows | low | Gating group *creation* hurts the network more than it earns. |
| Photo uploads per post | storage + Rekognition, **real money** | medium | The only limit that is actually about cost. |
| Ads | — | — | The free tier's actual price. |
| Export (CSV) | — | — | Doesn't exist yet; a natural premium-only feature when it does. |

### What must never be gated, for reasons other than kindness

- **Account deletion**, reporting, blocking — App Store guideline 5.1.1(v) and
  1.2. Paywalling any of these is a rejection.
- **The privacy policy link**, support contact — same.
- **Moderation.** Every uploaded image is checked on both tiers. A cheaper tier
  with less safety is not a cheaper tier.

---

## Three ways to draw the line

### Option A — Accumulation only — **chosen**

Free keeps every feature and every screen. What it cannot do is *pile up*.

| | Free | Premium |
|---|---|---|
| Logging | unlimited | unlimited |
| Saved meal library | **20** | unlimited |
| Tracker history | **last 7 days** | all of it |
| Weekly recap | current week | every week |
| Active challenges | **1** | unlimited |
| Insights & trends | all of them | all of them |
| Ads | banner + occasional interstitial | none |
| Rewarded ads | available (streak restore, 24h ad-free) | not needed |

**Why this one.** Every limit bites later rather than sooner, so a new user
experiences a complete app and a three-month user experiences a wall they have
a reason to pay through. Nothing is hidden behind a lock icon on day one, which
is the pattern that makes people uninstall rather than upgrade. And it is the
cheapest to maintain: premium is the same app with the ceilings removed, so
there is no second set of screens to keep working.

**Risk.** Somebody who never saves meals and never scrolls back may never hit
anything. That is what `plan_limit_reached` in analytics is for — if nobody
fires it, the numbers are wrong and they are one line each to change.

### Option B — Accumulation plus depth ("less analytics") — not taken

Option A, and the analysis screens are thinner on free.

| | Free | Premium |
|---|---|---|
| everything in Option A | | |
| Dashboard trend cards | current weight + goal | + rate, projection, BMI, full chart |
| Insights list | 1 card | all of them |
| Weight chart | last 30 days | all of it |

**Why.** "Less analytics" is what you said, and this is what it looks like. It
raises the number of people who hit *something*, because the dashboard is
opened far more often than the meal library fills up.

**Risk.** This is the option that makes the free app feel *cut down* rather
than *finite*, and the insights are computed from data the user already gave
us — a locked card over arithmetic reads as petty in a way a full library does
not. If you take this, lock the *projection* and the *chart history*, not the
advice: advice is what makes the app feel like it is paying attention, and a
user who feels ignored on day two never reaches day ninety.

### Option C — Photos and social, too — not taken

Option B, plus: free gets 1 photo per post, premium 4. Free gets 3 groups,
premium unlimited.

**Why.** The photo limit is the only one that maps to a cost we actually pay
(storage plus $0.001 of Rekognition per image).

**Risk.** It is also the limit most likely to reduce posting, and posting is
what makes the feed worth opening for everyone else. A quieter feed costs more
than the storage saves — at this scale, much more. **Not recommended until the
app is large enough that image spend is visible on a bill.**

---

## Why A, and why this price

The pitch has to be a sentence anyone can repeat: **"the app, without
ceilings, without ads."** "The app, but with more analytics" is not that, and
it invites a comparison with free apps that have plenty of analytics.

If conversion is flat after a month, the first thing to try is two of Option
B's lines — lock the *projection* and the *chart history*, leave the insights
alone — rather than tightening A's numbers. Advice is what makes the app feel
like it is paying attention; a user who feels ignored on day two never reaches
day ninety.

On the price: this is towards the top of the category per month (MyFitnessPal
Premium ~$20/mo or ~$80/yr, Cronometer Gold ~$50/yr, MacroFactor ~$12/mo or
~$72/yr) and below all of them per year, which is where this category actually
converts. That is the trade being made deliberately.

A **discounted introductory price** is worth keeping in reserve — the trial
above uses the free variety of the same mechanism, and a paid one is better
spent later on a win-back than at launch, when there is nobody to win back.

---

## What is built

- **The entitlement** — `subscriptions`, `is_premium()`, an app-wide cubit,
  and a cached client copy that decides presentation only.
- **Ads** — a banner in the feed, interstitials at two seams under six rules,
  and rewarded videos for a day without ads and for restoring a broken streak.
  See `docs/ADMOB.md`.
- **Buying it** — `in_app_purchase`, the upgrade screen, restore purchases,
  and `verify-purchase`, which asks the store itself and writes
  `subscriptions` with the service key. **The app never writes that table** —
  see the header of `supabase/premium.sql`.
- **The limits** — `premium_limits.sql`. The meal library and the challenge
  cap are enforced by triggers raising their own SQLSTATE, so the app can say
  "you have reached the 20 meals a free account keeps" rather than "you do not
  have permission". The history window is gated in the app only, and the
  header of that file says why: restricting reads of `daily_logs` would also
  cap every free account's streak at seven days, which is a worse bug than the
  thing it prevents.

## What is not built yet

Still to come:

1. **The upgrade prompt at every wall.** The meal library and the tracker's
   history both offer it; joining a second challenge currently just says why
   it failed. The sentence is right either way — `plan_limit_error.dart`
   supplies it — but a limit with a button beats a limit with an explanation.
2. **The two products in App Store Connect and Play Console.** Everything
   else about buying is built; this is what it needs to exist. Ids, prices and
   the trial are in the table at the top of this file. Until they exist, the
   upgrade screen says the store is unreachable, which is the truth.

   **On Play, the trial is an *offer* on the yearly base plan**, not a setting
   on the subscription. Adding it makes `queryProductDetails` answer with two
   entries for `bulkr_premium_yearly` — the base plan and the offer — and the
   app folds them back into one row (`PremiumPlan`). Two things depend on that
   fold and are easy to get wrong by hand: the price shown must come from the
   first *non-free* pricing phase, and the billing flow must be handed the
   **offer**, because launching it with the base plan buys the subscription
   without the trial and charges the buyer today without saying so.

   **Play returns nothing at all until a build is on a track.** Internal
   testing is enough, but the upload must carry the same `applicationId`
   (`com.alimahmoud.bulkr`), be signed with the key Play expects, and the
   account testing it must be on the tester list and have opted in. An empty
   product list is the normal symptom of that, not of a code problem.

   The trial needs no client work: a subscription in its trial is premium, and
   `subscriptions.expires_at` is simply the end of the trial. Nothing in the
   app distinguishes the two, deliberately — a trial user is a premium user,
   and a second state to reason about is a second state to get wrong. A trial
   that ends without a payment is a normal lapse.

3. **Server notifications.** Apple's App Store Server Notifications V2 and
   Google's Real-time Developer Notifications. Without them a *refund* is
   never noticed, because it revokes access without changing any date. A
   lapse is survivable without them — `expires_at` makes the row degrade on
   its own — so this is worth doing before there are enough subscribers for
   one refund to matter, and not before.
