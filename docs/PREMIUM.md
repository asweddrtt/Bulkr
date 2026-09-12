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

No free trial at launch. It lifts conversion, and it also lands the first
charge a week after the excitement wears off, which is where refund requests
come from — worth revisiting once there are enough subscribers to measure
churn against.

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

An **introductory price** is worth keeping in reserve. Both stores support it,
and it is better spent later on a win-back than at launch, when there is
nobody to win back.

---

## What is not built yet

This slice built the *answer* — who is premium — and nothing that acts on it.
Still to come:

1. **Ads** (next slice): banner in the feed, interstitial after a completed
   action and on returning after 4+ hours, rewarded for streak restore and 24
   hours ad-free. All of them gated on `EntitlementState.showsAds`.
2. **Enforcement**: the `free_*()` functions exist and no policy calls them
   yet. Each is one `and (public.is_premium(auth.uid()) or <count> < ...)`
   added to a policy that already exists.
3. **The purchase itself**: `in_app_purchase`, the products above in App Store
   Connect and Play Console, and an edge function that verifies the receipt
   with the store and writes `subscriptions` with the service key. **The app
   never writes that table** — see the header of `supabase/premium.sql`.
4. **The upgrade screen**, and the `paywall_shown` / `upgrade_*` events that
   are already defined and currently fired by nothing.
