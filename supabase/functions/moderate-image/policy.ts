// What Bulkr refuses, and — just as importantly — what it must not.
//
// Rekognition answers with a hierarchy rather than a score, and that is the
// whole reason it was chosen over a single "adult: LIKELY" number. A bulking
// app's best content is a shirtless progress photo. The moderation problem
// here is not catching nudes; any modern model does that. It is not rejecting
// the photo the app exists to collect.
//
// So the policy is a list of names, not a threshold, and it is written to be
// read by a person deciding whether it is right.
//
// Kept in its own file with no I/O so it can be tested without AWS, a network,
// or a deploy — `policy.test.ts`, same pattern as `food-search/usda.ts`.

/** One label as Rekognition returns it. */
export interface ModerationLabel {
  /** e.g. "Exposed Male Genitalia" */
  Name?: string;
  /** 0-100. */
  Confidence?: number;
  /** The top-level category, e.g. "Explicit". Empty for a top-level label. */
  ParentName?: string;
}

export type Verdict = "allow" | "refuse";

export interface Decision {
  verdict: Verdict;
  /** The label that caused a refusal, for the log. Null when allowed. */
  reason: string | null;
  /** Its confidence, for calibration. */
  confidence: number | null;
  /** Every label above the reporting floor, for telemetry and tuning. */
  observed: Array<{ name: string; confidence: number }>;
}

/**
 * Labels that refuse the upload, with the confidence each needs.
 *
 * Two bands, and the difference is how costly a false positive is:
 *
 *   0.8  Sexual content. A wrong refusal here is annoying but the user
 *        understands why an app refused it, and the cost of a miss is an
 *        explicit image on a public feed.
 *   0.9  Everything else. These are rarer and more likely to be confused by
 *        gym imagery, so they have to be more certain before they act.
 *
 * Names are Rekognition's, spelled exactly. A renamed label in a future
 * taxonomy version silently stops matching, which is why `UNKNOWN_LABEL_FLOOR`
 * below exists as a backstop.
 */
export const REFUSE: ReadonlyMap<string, number> = new Map([
  // --- Sexual content -----------------------------------------------------
  ["Explicit", 0.8],
  ["Explicit Nudity", 0.8],
  ["Exposed Male Genitalia", 0.8],
  ["Exposed Female Genitalia", 0.8],
  ["Exposed Buttocks or Anus", 0.8],
  ["Exposed Female Nipple", 0.8],
  ["Explicit Sexual Activity", 0.8],
  ["Sex Toys", 0.8],
  ["Sexual Activity", 0.8],

  // --- Other things a social feed should not carry ------------------------
  ["Hate Symbols", 0.9],
  ["Nazi Party", 0.9],
  ["White Supremacy", 0.9],
  ["Extremist", 0.9],
  ["Graphic Violence", 0.9],
  ["Explosions and Blasts", 0.9],
  ["Self-Harm", 0.9],
]);

/**
 * Labels that must never refuse, whatever their confidence.
 *
 * This half is the one that matters for this app specifically, and it is not
 * merely "not in the refuse list" — it is an explicit statement that these are
 * *expected*, so that a future widening of [REFUSE] or a new parent category
 * cannot quietly start rejecting the feed's normal content.
 *
 * `Emaciated Bodies` is the subtle one and it is here deliberately. It sits
 * under Rekognition's "Visually Disturbing" parent, and a very lean
 * bodybuilder at low body fat is exactly the thing it is most likely to fire
 * on. Refusing a cutting photo as "visually disturbing" would be both wrong
 * and insulting, so that whole branch stays out.
 */
export const NEVER_REFUSE: ReadonlySet<string> = new Set([
  "Swimwear or Underwear",
  "Male Swimwear Or Underwear",
  "Female Swimwear Or Underwear",
  "Non-Explicit Nudity",
  "Non-Explicit Nudity of Intimate parts and Kissing",
  "Implied Nudity",
  "Obstructed Intimate Parts",
  "Obstructed Female Nipple",
  "Kissing on the Lips",
  "Barechested Male",
  // See the note above. A shredded physique is not a medical emergency.
  "Emaciated Bodies",
  "Visually Disturbing",
  "Weapons",
  "Products",
  "Alcohol",
  "Alcoholic Beverages",
  "Drinking",
]);

/**
 * A label under the "Explicit" parent that this policy has never heard of is
 * still refused at this confidence.
 *
 * Rekognition's taxonomy changes between model versions — v7 renamed several
 * v6 labels. A policy that matches only on exact names degrades the wrong way
 * when that happens: new labels appear, nothing matches, and everything is
 * allowed. Which is the same fail-open shape that made the on-device check
 * useless for a year.
 *
 * So an unrecognised label whose *parent* is a category we refuse is refused
 * too, unless it is named in [NEVER_REFUSE].
 */
export const UNKNOWN_LABEL_FLOOR = 0.9;

/** Parents whose unrecognised children are refused. See above. */
export const REFUSE_UNKNOWN_UNDER: ReadonlySet<string> = new Set([
  "Explicit",
  "Explicit Nudity",
  "Sexual Activity",
  "Hate Symbols",
]);

/** Labels below this are not worth reporting or acting on. */
export const REPORTING_FLOOR = 0.5;

/**
 * Decides what to do with one image's labels.
 *
 * Pure. Everything about whether Bulkr accepts a photo is decidable from this
 * function and a list of names, which is the point: the rule can be read,
 * argued with, and tested without an AWS account.
 */
export function decide(labels: readonly ModerationLabel[]): Decision {
  const observed: Array<{ name: string; confidence: number }> = [];

  // The refusal to report, chosen by specificity first and confidence second.
  //
  // Rekognition returns the parent alongside the child — "Explicit" at 99.1
  // beside "Exposed Male Genitalia" at 98.4 — and picking on confidence alone
  // reports the parent, which is the less useful of the two. "Explicit" tells
  // a moderator nothing; the child names what was actually seen, which is what
  // a log, an appeal, and any future calibration all need.
  let worst: { name: string; confidence: number; specific: boolean } | null =
    null;

  for (const label of labels) {
    const name = (label.Name ?? "").trim();
    if (name === "") continue;

    const parent = (label.ParentName ?? "").trim();
    // A label with a parent is a leaf of the taxonomy: the specific thing.
    const specific = parent !== "";

    // Rekognition reports 0-100; everything here works in 0-1 so it reads the
    // same as the thresholds above and the same as the old on-device score.
    const confidence = (label.Confidence ?? 0) / 100;
    if (confidence < REPORTING_FLOOR) continue;

    observed.push({ name, confidence });

    if (NEVER_REFUSE.has(name)) continue;

    const required = REFUSE.get(name) ??
      (REFUSE_UNKNOWN_UNDER.has(parent) ? UNKNOWN_LABEL_FLOOR : null);

    if (required === null) continue;
    if (confidence < required) continue;

    const beatsCurrent = worst === null ||
      // A specific label always displaces a bare parent...
      (specific && !worst.specific) ||
      // ...and among equals, the more confident one wins.
      (specific === worst.specific && confidence > worst.confidence);

    if (beatsCurrent) worst = { name, confidence, specific };
  }

  observed.sort((a, b) => b.confidence - a.confidence);

  return worst === null
    ? { verdict: "allow", reason: null, confidence: null, observed }
    : {
      verdict: "refuse",
      reason: worst.name,
      confidence: worst.confidence,
      observed,
    };
}
