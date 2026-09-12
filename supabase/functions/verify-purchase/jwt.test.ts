// Run: node --experimental-strip-types supabase/functions/verify-purchase/jwt.test.ts
//
// The half of purchase verification that can be tested without a store
// account. Nothing here needs Apple, Google, or a device.
//
// The tokens this signs are the only thing standing between a forged receipt
// and a free subscription — if a signature is malformed, both stores answer
// 401 and *every* purchase silently fails to verify, which looks exactly like
// nobody buying anything.

import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import {
  b64url,
  b64urlText,
  decodeJwsPayload,
  fromB64url,
  signAppleJwt,
  signGoogleJwt,
} from "./jwt.ts";

// Deno has `crypto.subtle` globally; Node needs it wired up before the module
// under test runs.
if (!globalThis.crypto) {
  (globalThis as { crypto?: Crypto }).crypto = webcrypto as unknown as Crypto;
}

let passed = 0;
async function check(name: string, run: () => void | Promise<void>) {
  try {
    await run();
    passed++;
  } catch (error) {
    console.error(`FAIL  ${name}\n      ${error}`);
    process.exitCode = 1;
  }
}

function pem(der: ArrayBuffer, label: string): string {
  const base64 = Buffer.from(der).toString("base64");
  const lines = base64.match(/.{1,64}/g) ?? [];
  return `-----BEGIN ${label}-----\n${lines.join("\n")}\n-----END ${label}-----`;
}

// --- base64url -------------------------------------------------------------

await check("base64url drops padding and is URL safe", () => {
  // A JWT segment containing `+` or `/` is a JWT that breaks in a URL, and the
  // failure is a 401 from a store rather than anything that names the cause.
  const encoded = b64url(new Uint8Array([251, 255, 190, 255]));

  assert.ok(!encoded.includes("+"));
  assert.ok(!encoded.includes("/"));
  assert.ok(!encoded.includes("="));
});

await check("round-trips text of every length mod 4", () => {
  // Padding is where base64 implementations disagree, and the lengths that
  // expose it are exactly these four.
  for (const text of ["a", "ab", "abc", "abcd", "{}"]) {
    assert.equal(fromB64url(b64urlText(text)), text);
  }
});

await check("round-trips non-ASCII", () => {
  // Display names and product titles are not ASCII, and a JSON payload that
  // loses a character is a signature over different bytes than the ones sent.
  const text = JSON.stringify({ name: "Bulkr — 39,99 €" });
  assert.equal(fromB64url(b64urlText(text)), text);
});

// --- Reading a JWS ---------------------------------------------------------

await check("reads the payload of a three-part JWS", () => {
  const jws = [
    b64urlText(JSON.stringify({ alg: "ES256" })),
    b64urlText(JSON.stringify({ transactionId: "2000000123456789" })),
    "signature",
  ].join(".");

  assert.equal(decodeJwsPayload(jws)?.transactionId, "2000000123456789");
});

await check("answers null rather than throwing on rubbish", () => {
  // This is called on a blob the *client* supplied. A malformed one has to be
  // a rejected request, not a 500 — and certainly not an exception out of a
  // path that is otherwise about to write a subscription.
  assert.equal(decodeJwsPayload("not a jws"), null);
  assert.equal(decodeJwsPayload("a.b.c"), null);
  assert.equal(decodeJwsPayload(""), null);
  assert.equal(decodeJwsPayload(`${b64urlText("[]")}.${b64urlText("[]")}.x`), null);
});

// --- Apple, ES256 ----------------------------------------------------------

await check("the Apple token verifies against its own key", async () => {
  const pair = await webcrypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );

  const token = await signAppleJwt({
    keyId: "ABC123DEFG",
    issuerId: "57246542-96fe-1a63-e053-0824d011072a",
    bundleId: "com.alimahmoud.bulkr",
    privateKeyPem: pem(
      await webcrypto.subtle.exportKey("pkcs8", pair.privateKey),
      "PRIVATE KEY",
    ),
  });

  const [header, payload, signature] = token.split(".");

  const ok = await webcrypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    Buffer.from(signature.replace(/-/g, "+").replace(/_/g, "/"), "base64"),
    Buffer.from(`${header}.${payload}`),
  );

  assert.ok(ok, "Apple would reject this token");
});

await check("the Apple token carries what Apple checks", async () => {
  const pair = await webcrypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );

  const token = await signAppleJwt({
    keyId: "ABC123DEFG",
    issuerId: "issuer-1",
    bundleId: "com.alimahmoud.bulkr",
    privateKeyPem: pem(
      await webcrypto.subtle.exportKey("pkcs8", pair.privateKey),
      "PRIVATE KEY",
    ),
  });

  const [rawHeader, rawPayload] = token.split(".");
  const header = JSON.parse(fromB64url(rawHeader));
  const payload = JSON.parse(fromB64url(rawPayload));

  assert.equal(header.alg, "ES256");
  assert.equal(header.kid, "ABC123DEFG");
  assert.equal(payload.iss, "issuer-1");
  assert.equal(payload.aud, "appstoreconnect-v1");
  assert.equal(payload.bid, "com.alimahmoud.bulkr");

  // Apple rejects anything over an hour, and a token that has already expired
  // when it is minted fails in a way that looks like a wrong key.
  const life = payload.exp - payload.iat;
  assert.ok(life > 0 && life <= 3600, `token life is ${life}s`);
});

await check("a PEM whose newlines became literal \\n still works", async () => {
  // The realistic failure. These keys are pasted into a dashboard or an env
  // file, and both routinely turn the line breaks in a .p8 into backslash-n.
  const pair = await webcrypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );

  const armoured = pem(
    await webcrypto.subtle.exportKey("pkcs8", pair.privateKey),
    "PRIVATE KEY",
  );

  const token = await signAppleJwt({
    keyId: "K",
    issuerId: "I",
    bundleId: "B",
    privateKeyPem: armoured.replace(/\n/g, "\\n"),
  });

  assert.equal(token.split(".").length, 3);
});

// --- Google, RS256 ---------------------------------------------------------

await check("the Google assertion verifies against its own key", async () => {
  const pair = await webcrypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );

  const token = await signGoogleJwt({
    clientEmail: "bulkr@bulkr.iam.gserviceaccount.com",
    privateKeyPem: pem(
      await webcrypto.subtle.exportKey("pkcs8", pair.privateKey),
      "PRIVATE KEY",
    ),
    scope: "https://www.googleapis.com/auth/androidpublisher",
  });

  const [header, payload, signature] = token.split(".");

  const ok = await webcrypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    pair.publicKey,
    Buffer.from(signature.replace(/-/g, "+").replace(/_/g, "/"), "base64"),
    Buffer.from(`${header}.${payload}`),
  );

  assert.ok(ok, "Google would reject this assertion");

  const claims = JSON.parse(fromB64url(payload));
  assert.equal(claims.aud, "https://oauth2.googleapis.com/token");
  assert.equal(claims.scope, "https://www.googleapis.com/auth/androidpublisher");
});

console.log(`${passed} passed`);
