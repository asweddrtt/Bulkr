// Does this photo belong on the feed? Asked of AWS Rekognition, server-side.
//
// It runs here rather than on the device for two reasons, and the second is
// the one that matters:
//
//   1. The AWS credentials are not shipped in the binary. An .apk is a zip.
//   2. The *model* is not shipped either. The on-device check this replaces
//      was a 2016 classifier that, on iOS, scored a full nude below a topless
//      photo — and on Android never ran at all, because its model 404s. See
//      lib/core/image_safety.dart for that whole story.
//
// Deploy:
//   supabase link --project-ref hqdfaeiyflbbzkduskaz
//   supabase secrets set REKOGNITION_ACCESS_KEY_ID=... \
//                        REKOGNITION_SECRET_ACCESS_KEY=... \
//                        REKOGNITION_REGION=us-east-1
//   supabase functions deploy moderate-image
//
// The caller's JWT is verified by the platform, so only signed-in users reach
// this. See README.md for the IAM policy — it needs exactly one action.

import {
  DetectModerationLabelsCommand,
  RekognitionClient,
} from "npm:@aws-sdk/client-rekognition@3";

import { decide, type ModerationLabel } from "./policy.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/// Rekognition's own cap on inline bytes. The app resizes before it gets here,
/// so this is a guard against a caller that did not rather than a normal path.
const MAX_BYTES = 5 * 1024 * 1024;

/// Below this Rekognition does not report a label at all. Lower than the
/// policy's own thresholds on purpose: the extra labels are what make the
/// telemetry useful for tuning, and the policy decides separately what to act
/// on.
const MIN_CONFIDENCE = 50;

/// The SDK client is created once per isolate rather than per request, so a
/// warm function pays no setup at all.
let client: RekognitionClient | null = null;

function rekognition(): RekognitionClient {
  if (client) return client;

  const accessKeyId = Deno.env.get("REKOGNITION_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("REKOGNITION_SECRET_ACCESS_KEY");

  if (!accessKeyId || !secretAccessKey) {
    // Named rather than generic: a missing secret and a wrong secret fail in
    // completely different places, and this is the one that is a deploy step
    // somebody forgot.
    throw new Error(
      "REKOGNITION_ACCESS_KEY_ID / REKOGNITION_SECRET_ACCESS_KEY are not set. " +
        "See supabase/functions/moderate-image/README.md.",
    );
  }

  client = new RekognitionClient({
    region: Deno.env.get("REKOGNITION_REGION") ?? "us-east-1",
    credentials: { accessKeyId, secretAccessKey },
  });

  return client;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const started = Date.now();

  try {
    const body = await request.json().catch(() => null);
    const base64 = typeof body?.image === "string" ? body.image : "";

    if (base64 === "") {
      return json({ error: "no image" }, 400);
    }

    let bytes: Uint8Array;
    try {
      bytes = base64ToBytes(base64);
    } catch {
      return json({ error: "image is not valid base64" }, 400);
    }

    if (bytes.byteLength === 0) return json({ error: "empty image" }, 400);
    if (bytes.byteLength > MAX_BYTES) {
      return json({ error: "image too large", limit: MAX_BYTES }, 413);
    }

    const response = await rekognition().send(
      new DetectModerationLabelsCommand({
        Image: { Bytes: bytes },
        MinConfidence: MIN_CONFIDENCE,
      }),
    );

    const labels = (response.ModerationLabels ?? []) as ModerationLabel[];
    const decision = decide(labels);

    return json({
      verdict: decision.verdict,
      reason: decision.reason,
      confidence: decision.confidence,
      observed: decision.observed,
      // Which taxonomy produced this. Worth returning: the label names the
      // policy matches on are version-specific, so a bump here is the first
      // thing to look at if refusals suddenly change shape.
      modelVersion: response.ModerationModelVersion ?? null,
      ms: Date.now() - started,
    });
  } catch (error) {
    // Deliberately a 5xx with no verdict rather than a cheerful "allow".
    //
    // The client decides what to do when moderation is unavailable, and that
    // decision belongs there where it can be seen — see `ModerationService` in
    // the app. A function that answered "allow" on its own failure would be
    // the same silent fail-open that made the previous check worthless, just
    // moved to a different machine.
    console.error("moderate-image failed:", error);

    return json({
      error: "moderation unavailable",
      detail: error instanceof Error ? error.message : String(error),
    }, 502);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/// Base64 to bytes without pulling in a dependency for it.
function base64ToBytes(value: string): Uint8Array {
  // Tolerates a data: URL prefix, because it is the single most likely thing
  // for a caller to send by accident and rejecting it is not worth a support
  // round trip.
  const clean = value.includes(",") ? value.slice(value.indexOf(",") + 1) : value;
  const binary = atob(clean);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
