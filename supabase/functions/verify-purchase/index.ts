// Turning a purchase into an entitlement, without believing the client.
//
// The app cannot write `subscriptions` — there is no insert policy on it, by
// design (see supabase/premium.sql). A purchase becomes premium here, or it
// does not become premium at all.
//
// ## What is and is not trusted
//
// The request body carries a receipt. **Nothing in it is trusted.** What
// happens is:
//
//   iOS      the client's blob is opened only far enough to read a
//            transaction id, and then Apple is asked what that transaction
//            actually is. The answer comes from Apple over TLS, authenticated
//            with our own signed JWT.
//   Android  the purchase token is sent straight to Google, which answers with
//            the subscription's real state.
//
// So a forged receipt buys nothing: the worst it can do is name a transaction
// id that does not exist, or that belongs to somebody else — and the second of
// those is closed by `store_id` being unique on `subscriptions`, so a purchase
// already attached to one account cannot be attached to another.
//
// The user id comes from the verified JWT and never from the body, for the
// same reason it does in `delete-account`.
//
// ## Deploy
//
//   supabase functions deploy verify-purchase
//
// See README.md in this directory for the eight environment variables and
// where each one comes from.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decodeJwsPayload, signAppleJwt, signGoogleJwt } from "./jwt.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/// What both stores are reduced to before anything is written.
interface Verdict {
  active: boolean;
  expiresAt: string | null;
  storeId: string;
  /// Which plan, as the *store* reported it. The request body carries one too
  /// and it is ignored: nothing here is taken from the client, including the
  /// parts that only label a screen.
  productId: string | null;
  source: "app_store" | "play";
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !serviceRole) {
    console.error("verify-purchase: missing SUPABASE_URL or service role key");
    return json({ error: "not_configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(url, serviceRole, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: caller, error: callerError } = await admin.auth.getUser(
    authorization.replace(/^[Bb]earer\s+/, ""),
  );

  if (callerError || !caller?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: { platform?: string; receipt?: string; productId?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const platform = body.platform;
  const receipt = body.receipt;

  if (typeof receipt !== "string" || receipt.length === 0) {
    return json({ error: "bad_request", detail: "receipt is required" }, 400);
  }

  let verdict: Verdict;
  try {
    if (platform === "ios") {
      verdict = await verifyApple(receipt);
    } else if (platform === "android") {
      verdict = await verifyGoogle(receipt, body.productId);
    } else {
      return json({ error: "bad_request", detail: "unknown platform" }, 400);
    }
  } catch (error) {
    // A 502 rather than a cheerful "not premium", for the same reason
    // moderate-image returns one: a verification that could not run is not the
    // same answer as a verification that said no, and the client has to be
    // able to tell them apart in order to retry.
    console.error("verify-purchase: verification failed", error);
    return json({ error: "verification_failed", detail: `${error}` }, 502);
  }

  const userId = caller.user.id;

  // `store_id` is unique, so this also closes the "one purchase, two accounts"
  // hole: the second account's upsert collides and is rejected rather than
  // quietly moving the subscription.
  const { error: writeError } = await admin
    .from("subscriptions")
    .upsert({
      user_id: userId,
      tier: verdict.active ? "premium" : "free",
      expires_at: verdict.expiresAt,
      source: verdict.source,
      store_id: verdict.storeId,
      product_id: verdict.productId,
    }, { onConflict: "user_id" });

  if (writeError) {
    // 23505 is a unique violation, which here means this purchase is already
    // attached to a different account. That is not a server error and the app
    // says something specific about it — it is nearly always somebody with two
    // accounts on one phone, not an attack.
    if (writeError.code === "23505") {
      console.warn("verify-purchase: store_id already claimed", verdict.storeId);
      return json({ error: "already_claimed" }, 409);
    }

    console.error("verify-purchase: could not write subscription", writeError);
    return json({ error: "write_failed", detail: writeError.message }, 500);
  }

  return json({
    premium: verdict.active,
    expiresAt: verdict.expiresAt,
    source: verdict.source,
  }, 200);
});

// ---------------------------------------------------------------------------
// Apple
// ---------------------------------------------------------------------------

/// Asks the App Store Server API what a transaction really is.
///
/// The client's `serverVerificationData` is a signed transaction (StoreKit 2).
/// Its signature could be checked here against Apple's certificate chain, and
/// deliberately is not: the chain has to be fetched, cached and rotated, and
/// the same guarantee comes for free from asking Apple directly. So the blob
/// is opened only to read `transactionId` — a hint, not evidence — and every
/// fact that follows comes from Apple's own answer.
async function verifyApple(receipt: string): Promise<Verdict> {
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const issuerId = Deno.env.get("APPLE_ISSUER_ID");
  const bundleId = Deno.env.get("APPLE_BUNDLE_ID");
  const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY");

  if (!keyId || !issuerId || !bundleId || !privateKeyPem) {
    throw new Error(
      "APPLE_KEY_ID / APPLE_ISSUER_ID / APPLE_BUNDLE_ID / APPLE_PRIVATE_KEY are not set",
    );
  }

  const transactionId = appleTransactionId(receipt);
  if (!transactionId) throw new Error("no transaction id in the receipt");

  const token = await signAppleJwt({
    keyId,
    issuerId,
    bundleId,
    privateKeyPem,
  });

  // Production first, then sandbox. Apple does not tell you which environment
  // a receipt belongs to up front, and TestFlight builds buy in sandbox while
  // pointing at the same code — so a production-only check works right up
  // until the first person tests it.
  const hosts = [
    "https://api.storekit.itunes.apple.com",
    "https://api.storekit-sandbox.itunes.apple.com",
  ];

  for (const host of hosts) {
    const response = await fetch(
      `${host}/inApps/v1/subscriptions/${transactionId}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );

    // 404 means "not in this environment", which is the signal to try the
    // other one rather than to give up.
    if (response.status === 404) continue;

    if (!response.ok) {
      throw new Error(`App Store Server API ${response.status}`);
    }

    const payload = await response.json();
    return appleVerdict(payload, transactionId);
  }

  throw new Error("transaction not found in either environment");
}

/// The transaction id inside the client's blob.
///
/// Handles both shapes the Flutter plugin can produce: a StoreKit 2 signed
/// transaction (a JWS, three dot-separated parts) and a bare id. A StoreKit 1
/// base64 receipt is not accepted — see the README for why the app is
/// configured to use StoreKit 2.
function appleTransactionId(receipt: string): string | null {
  if (receipt.split(".").length === 3) {
    const payload = decodeJwsPayload(receipt);
    const id = payload?.originalTransactionId ?? payload?.transactionId;
    return typeof id === "string" ? id : null;
  }

  // A plain id. Digits only, because it goes straight into a URL path.
  return /^\d+$/.test(receipt) ? receipt : null;
}

function appleVerdict(
  payload: Record<string, unknown>,
  transactionId: string,
): Verdict {
  // `data` is one entry per subscription group. Bulkr has one group, but the
  // shape is a list either way.
  const groups = Array.isArray(payload.data) ? payload.data : [];

  let expiresAt: number | null = null;
  let active = false;
  let originalId = transactionId;
  let productId: string | null = null;

  for (const group of groups) {
    const transactions = Array.isArray((group as Record<string, unknown>)
        .lastTransactions)
      ? (group as Record<string, unknown>).lastTransactions as unknown[]
      : [];

    for (const entry of transactions) {
      const record = entry as Record<string, unknown>;

      // 1 = active, 2 = expired, 3 = in billing retry, 4 = in grace period,
      // 5 = revoked.
      //
      // 3 and 4 count as premium on purpose: the subscription has not ended,
      // Apple is retrying a payment, and taking the app away mid-retry from
      // somebody whose card was declined once is how a temporary problem
      // becomes a cancellation.
      const status = record.status;
      const isActive = status === 1 || status === 3 || status === 4;

      const signed = typeof record.signedTransactionInfo === "string"
        ? decodeJwsPayload(record.signedTransactionInfo)
        : null;

      const expiry = typeof signed?.expiresDate === "number"
        ? signed.expiresDate as number
        : null;

      if (typeof signed?.originalTransactionId === "string") {
        originalId = signed.originalTransactionId as string;
      }

      // The furthest expiry wins, which is what an upgrade mid-period looks
      // like: two transactions, one superseded.
      if (isActive && (expiresAt === null || (expiry ?? 0) > expiresAt)) {
        active = true;
        expiresAt = expiry;
        productId = typeof signed?.productId === "string"
          ? signed.productId as string
          : productId;
      }
    }
  }

  return {
    active,
    expiresAt: expiresAt === null ? null : new Date(expiresAt).toISOString(),
    storeId: originalId,
    productId,
    source: "app_store",
  };
}

// ---------------------------------------------------------------------------
// Google
// ---------------------------------------------------------------------------

/// Asks the Play Developer API what a purchase token really is.
///
/// Unlike Apple's, the token carries no readable payload at all, so there is
/// nothing here to be tempted to trust.
async function verifyGoogle(
  purchaseToken: string,
  _productId: string | undefined,
): Promise<Verdict> {
  const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE");
  const clientEmail = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL");
  const privateKeyPem = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_KEY");

  if (!packageName || !clientEmail || !privateKeyPem) {
    throw new Error(
      "GOOGLE_PLAY_PACKAGE / GOOGLE_SERVICE_ACCOUNT_EMAIL / GOOGLE_SERVICE_ACCOUNT_KEY are not set",
    );
  }

  const assertion = await signGoogleJwt({
    clientEmail,
    privateKeyPem,
    scope: "https://www.googleapis.com/auth/androidpublisher",
  });

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(`Google OAuth ${tokenResponse.status}`);
  }

  const { access_token: accessToken } = await tokenResponse.json();
  if (!accessToken) throw new Error("Google OAuth returned no access token");

  const response = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/` +
      `${encodeURIComponent(purchaseToken)}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );

  if (!response.ok) {
    throw new Error(`Play Developer API ${response.status}`);
  }

  const payload = await response.json();
  return googleVerdict(payload, purchaseToken);
}

function googleVerdict(
  payload: Record<string, unknown>,
  purchaseToken: string,
): Verdict {
  // SUBSCRIPTION_STATE_ACTIVE and _IN_GRACE_PERIOD are premium. _ON_HOLD,
  // _PAUSED, _EXPIRED, _CANCELED and _PENDING are not — with the caveat that
  // "canceled" in Play means "will not renew", and such a subscription is
  // still active until its expiry, which is why the date is read as well.
  const state = typeof payload.subscriptionState === "string"
    ? payload.subscriptionState
    : "";

  const lineItems = Array.isArray(payload.lineItems) ? payload.lineItems : [];

  let expiresAt: string | null = null;
  let productId: string | null = null;
  for (const item of lineItems) {
    const line = item as Record<string, unknown>;
    const expiry = line.expiryTime;
    if (typeof expiry !== "string") continue;

    if (expiresAt === null || expiry > expiresAt) {
      expiresAt = expiry;
      productId = typeof line.productId === "string" ? line.productId : null;
    }
  }

  const stillRunning = expiresAt !== null &&
    new Date(expiresAt).getTime() > Date.now();

  const active = state === "SUBSCRIPTION_STATE_ACTIVE" ||
    state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" ||
    (state === "SUBSCRIPTION_STATE_CANCELED" && stillRunning);

  return {
    active,
    expiresAt,
    // `linkedPurchaseToken` chains across upgrades, so the token we were given
    // is the one that identifies this purchase now. Apple's original
    // transaction id is stabler; Play has no equivalent that survives a plan
    // change, and this is the closest thing.
    storeId: purchaseToken,
    productId,
    source: "play",
  };
}
