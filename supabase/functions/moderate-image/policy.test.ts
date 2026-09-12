// Run: node --experimental-strip-types supabase/functions/moderate-image/policy.test.ts
//
// The half of moderation that can be tested without AWS. The policy is a list
// of names and two thresholds, and every decision Bulkr makes about a photo
// comes out of it — so it is worth more tests than the plumbing around it.
//
// The cases below are split deliberately: refusing nudity is the easy half and
// any model does it. The hard half, and the one this app gets judged on, is
// *not* refusing a shirtless progress photo.

import assert from "node:assert/strict";
import {
  decide,
  type ModerationLabel,
  NEVER_REFUSE,
  REFUSE,
  REFUSE_UNKNOWN_UNDER,
} from "./policy.ts";

let passed = 0;
function check(name: string, run: () => void) {
  try {
    run();
    passed++;
  } catch (error) {
    console.error(`FAIL  ${name}\n      ${error}`);
    process.exitCode = 1;
  }
}

/** Rekognition reports confidence 0-100. */
const label = (
  Name: string,
  Confidence: number,
  ParentName = "",
): ModerationLabel => ({ Name, Confidence, ParentName });

// --- The easy half ---------------------------------------------------------

check("refuses exposed genitalia", () => {
  const result = decide([
    label("Explicit", 99.1),
    label("Exposed Male Genitalia", 98.4, "Explicit"),
  ]);

  assert.equal(result.verdict, "refuse");
  assert.equal(result.reason, "Exposed Male Genitalia");
});

check("refuses explicit sexual activity", () => {
  assert.equal(
    decide([label("Explicit Sexual Activity", 94, "Explicit")]).verdict,
    "refuse",
  );
});

check("names the most confident reason, not the first", () => {
  // So the log says the clearest thing that was wrong with the image.
  const result = decide([
    label("Explicit", 82, ""),
    label("Exposed Male Genitalia", 97, "Explicit"),
  ]);

  assert.equal(result.reason, "Exposed Male Genitalia");
});

check("an unsure label does not refuse", () => {
  // 70% on a label needing 80%. Below the bar is below the bar — the whole
  // point of a named threshold is that it is not a vibe.
  assert.equal(
    decide([label("Exposed Female Nipple", 70, "Explicit")]).verdict,
    "allow",
  );
});

// --- The half this app is judged on ---------------------------------------

check("a shirtless progress photo is allowed", () => {
  // The single most important case in this file. This is the best content on
  // the platform and the thing a scalar "adult likelihood" model gets wrong.
  const result = decide([
    label("Barechested Male", 96),
    label("Swimwear or Underwear", 88),
    label("Male Swimwear Or Underwear", 85, "Swimwear or Underwear"),
  ]);

  assert.equal(result.verdict, "allow");
  assert.equal(result.reason, null);
});

check("a posing-trunks physique shot is allowed", () => {
  assert.equal(
    decide([
      label("Male Swimwear Or Underwear", 99, "Swimwear or Underwear"),
      label("Non-Explicit Nudity", 74, ""),
    ]).verdict,
    "allow",
  );
});

check("a very lean cutting photo is not 'visually disturbing'", () => {
  // Rekognition files Emaciated Bodies under Visually Disturbing, and a
  // bodybuilder at low body fat is exactly what it fires on. Refusing a
  // cutting photo would be wrong and insulting, so that branch is excluded by
  // name rather than by luck.
  const result = decide([
    label("Visually Disturbing", 91),
    label("Emaciated Bodies", 88, "Visually Disturbing"),
  ]);

  assert.equal(result.verdict, "allow");
});

check("an obstructed or implied shot is allowed", () => {
  assert.equal(
    decide([
      label("Non-Explicit Nudity of Intimate parts and Kissing", 93),
      label("Obstructed Intimate Parts", 90, "Non-Explicit Nudity"),
    ]).verdict,
    "allow",
  );
});

check("a gym photo with a protein shake is allowed", () => {
  assert.equal(
    decide([label("Alcohol", 61), label("Drinking", 58)]).verdict,
    "allow",
  );
});

check("an ordinary meal photo is allowed", () => {
  assert.equal(decide([]).verdict, "allow");
});

// --- Degrading in the safe direction --------------------------------------

check("an unknown label under Explicit is still refused", () => {
  // Rekognition renames labels between taxonomy versions. A policy matching
  // only exact names fails open when that happens — new label, no match,
  // everything allowed — which is precisely the shape of the on-device bug
  // this replaced. So an unrecognised child of a refused parent is refused.
  const result = decide([
    label("Some Future Explicit Label", 95, "Explicit"),
  ]);

  assert.equal(result.verdict, "refuse");
  assert.equal(result.reason, "Some Future Explicit Label");
});

check("an unknown label under Explicit needs high confidence", () => {
  assert.equal(
    decide([label("Some Future Explicit Label", 85, "Explicit")]).verdict,
    "allow",
  );
});

check("an allow-listed label stays allowed even under a refused parent", () => {
  // The allow list wins. A taxonomy reshuffle that reparents swimwear under
  // Explicit must not start rejecting half the feed.
  assert.equal(
    decide([label("Male Swimwear Or Underwear", 99, "Explicit")]).verdict,
    "allow",
  );
});

check("an unknown label under a harmless parent is allowed", () => {
  assert.equal(
    decide([label("Some Future Food Label", 99, "Food and Beverage")]).verdict,
    "allow",
  );
});

// --- What gets reported ----------------------------------------------------

check("observed labels come back sorted, for calibration", () => {
  const result = decide([
    label("Barechested Male", 70),
    label("Swimwear or Underwear", 95),
  ]);

  assert.deepEqual(
    result.observed.map((o) => o.name),
    ["Swimwear or Underwear", "Barechested Male"],
  );
});

check("noise below the reporting floor is dropped", () => {
  assert.equal(decide([label("Whatever", 20)]).observed.length, 0);
});

check("confidence is reported 0-1, matching the thresholds", () => {
  const result = decide([label("Swimwear or Underwear", 88)]);
  assert.ok(Math.abs(result.observed[0].confidence - 0.88) < 1e-9);
});

check("a refusal carries the confidence that caused it", () => {
  const result = decide([label("Exposed Male Genitalia", 96, "Explicit")]);
  assert.ok(Math.abs(result.confidence! - 0.96) < 1e-9);
});

// --- Malformed input -------------------------------------------------------

check("a nameless label is ignored rather than crashing", () => {
  assert.equal(decide([{ Confidence: 99 }]).verdict, "allow");
});

check("a label with no confidence is treated as zero", () => {
  assert.equal(decide([{ Name: "Explicit" }]).verdict, "allow");
});

check("no labels at all is an allow", () => {
  assert.equal(decide([]).verdict, "allow");
});

// --- The policy itself -----------------------------------------------------

check("nothing is in both lists", () => {
  // A name in both would make the outcome depend on evaluation order, which
  // is the kind of thing that is discovered in production.
  for (const name of REFUSE.keys()) {
    assert.ok(
      !NEVER_REFUSE.has(name),
      `${name} is in both REFUSE and NEVER_REFUSE`,
    );
  }
});

check("every refuse threshold is a sane probability", () => {
  for (const [name, threshold] of REFUSE) {
    assert.ok(
      threshold > 0.5 && threshold <= 1,
      `${name} has an implausible threshold: ${threshold}`,
    );
  }
});

check("every unknown-label parent is itself a refused category", () => {
  // Otherwise the backstop would refuse children of a category the policy has
  // no opinion about.
  for (const parent of REFUSE_UNKNOWN_UNDER) {
    assert.ok(REFUSE.has(parent), `${parent} is a backstop parent but not refused`);
  }
});

console.log(`${passed} passed`);
