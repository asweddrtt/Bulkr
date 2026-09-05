// Sending a push.
//
// Invoked by a Supabase Database Webhook on `public.notifications` INSERT. It
// looks up where that notification should go, sends it through Firebase Cloud
// Messaging, and deletes any token FCM says is dead.
//
// Why a webhook rather than a trigger calling out directly: a trigger that
// makes an HTTP request holds a transaction open across the network, and a
// slow or unreachable FCM would turn "somebody liked your post" into a like
// that takes four seconds to record. The webhook fires after the row is
// committed, so the like is already saved whatever happens here.
//
// Why the app never calls this: it has no business being able to. The only
// input is a notification id, and `push_payload` is granted to `service_role`
// alone — an app that could call this could ask what any notification says.
//
// Deploy:
//   supabase functions deploy send-push --no-verify-jwt
//   supabase secrets set FCM_PROJECT_ID=... FCM_CLIENT_EMAIL=... FCM_PRIVATE_KEY=...
//   supabase secrets set PUSH_WEBHOOK_SECRET=...
//
// `--no-verify-jwt` because the caller is Postgres, not a signed-in user.
// PUSH_WEBHOOK_SECRET is what replaces that check: the webhook is configured
// to send it as a header, and a request without it is refused. Without that
// this endpoint would be "push anything to anyone who can guess a uuid".
//
// See README.md for the whole setup.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface PushTarget {
  token: string;
  platform: string | null;
  title: string;
  body: string;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// A Google access token for FCM, minted from the service account.
///
/// Signed here rather than pulled from a library so this function has one
/// dependency instead of five. The JWT is a bearer assertion Google exchanges
/// for an access token; it lives for an hour and is cached for slightly less.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Ten seconds of margin, so a token cannot expire between this check and the
  // request that uses it.
  if (cachedToken && cachedToken.expiresAt > now + 10) return cachedToken.value;

  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const rawKey = Deno.env.get("FCM_PRIVATE_KEY");

  if (!clientEmail || !rawKey) {
    throw new Error("FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY must be set");
  }

  // Secrets are set on one line, so the PEM's newlines arrive escaped.
  const pem = rawKey.replace(/\\n/g, "\n");

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  }));

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );

  const assertion = `${header}.${claim}.${base64UrlBytes(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`token exchange failed: ${await response.text()}`);
  }

  const body = await response.json();
  cachedToken = { value: body.access_token, expiresAt: now + 3500 };
  return cachedToken.value;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");

  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(text: string): string {
  return base64UrlBytes(new TextEncoder().encode(text));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!expected) return json({ error: "not_configured" }, 500);

  if (request.headers.get("x-push-secret") !== expected) {
    return json({ error: "forbidden" }, 403);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const projectId = Deno.env.get("FCM_PROJECT_ID");

  if (!url || !serviceRole || !projectId) {
    return json({ error: "not_configured" }, 500);
  }

  let notificationId: string | undefined;
  try {
    const payload = await request.json();
    // The webhook sends the whole row under `record`.
    notificationId = payload?.record?.id ?? payload?.id;
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  if (!notificationId) return json({ error: "bad_request" }, 400);

  const admin = createClient(url, serviceRole);

  const { data, error } = await admin.rpc("push_payload", {
    p_notification: notificationId,
  });

  if (error) return json({ error: error.message }, 500);

  const targets = (data ?? []) as PushTarget[];

  // Nothing to do is a success. A user with no devices registered, or one who
  // read the notification before this fired, is not a failure — and returning
  // an error would make the webhook retry something that will never work.
  if (targets.length === 0) return json({ sent: 0 }, 200);

  const bearer = await accessToken();
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const dead: string[] = [];
  let sent = 0;

  // One request per device. FCM v1 has no batch endpoint any more, and the
  // count here is the number of devices one person owns.
  await Promise.all(targets.map(async (target) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: target.token,
          notification: { title: target.title, body: target.body },
          data: { notification_id: notificationId },
          android: { priority: "high" },
        },
      }),
    });

    if (response.ok) {
      sent++;
      return;
    }

    // 404 is UNREGISTERED and 400 is usually an invalid token: the app was
    // uninstalled, or the token was rotated. Both mean this row will never
    // deliver again, so it goes rather than being retried forever.
    if (response.status === 404 || response.status === 400) {
      dead.push(target.token);
    }
  }));

  if (dead.length > 0) {
    await admin.from("device_tokens").delete().in("token", dead);
  }

  return json({ sent, removed: dead.length }, 200);
});
