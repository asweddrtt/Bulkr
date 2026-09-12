// Signing the tokens Apple and Google want, and reading the ones they send
// back.
//
// Separate from index.ts so it can be read on its own and tested without
// either store. Nothing here talks to the network.

/// base64url, without padding — what JWT uses everywhere.
export function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlText(text: string): string {
  return b64url(new TextEncoder().encode(text));
}

/// Decodes a base64url segment back to text. Tolerates the padding being
/// absent, which it always is.
export function fromB64url(segment: string): string {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(segment.length / 4) * 4, "=");

  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

  return new TextDecoder().decode(bytes);
}

/// The payload of a JWS, **without verifying the signature**.
///
/// Only ever called on a blob that came back from Apple over TLS, in response
/// to a request we authenticated ourselves. That is what makes it safe: the
/// transport is the proof, and re-verifying Apple's signature with Apple's own
/// certificate chain would prove the same thing twice.
///
/// It is also called on the receipt the *client* sends — and there the payload
/// is treated as a hint and nothing more. See the note on `appleTransactionId`
/// in index.ts.
export function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split(".");
  if (parts.length !== 3) return null;

  try {
    const decoded = JSON.parse(fromB64url(parts[1]));

    // An array is an object in JavaScript, and `[]` would otherwise come back
    // as a payload whose every field reads as undefined — which downstream
    // looks like a valid receipt for a transaction with no id, rather than
    // like the malformed input it is.
    return typeof decoded === "object" && decoded !== null &&
        !Array.isArray(decoded)
      ? decoded as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

/// Strips the PEM armour and returns the DER bytes.
///
/// Both keys arrive as PEM in an environment variable, and an environment
/// variable that has been through a shell, a dashboard text box, or a copy and
/// paste has usually lost its line breaks — so `\n` written literally is
/// restored as well.
function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");

  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/// ES256, for the App Store Server API.
///
/// Apple's key is an EC P-256 private key downloaded from App Store Connect as
/// a `.p8` file, which is PKCS#8 PEM.
export async function signAppleJwt(options: {
  keyId: string;
  issuerId: string;
  bundleId: string;
  privateKeyPem: string;
}): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(options.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);

  const header = {
    alg: "ES256",
    kid: options.keyId,
    typ: "JWT",
  };

  // Apple rejects anything over an hour. Twenty minutes is comfortably inside
  // that and long enough that clock skew on either side is irrelevant.
  const payload = {
    iss: options.issuerId,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1",
    bid: options.bundleId,
  };

  const signingInput = `${b64urlText(JSON.stringify(header))}.${
    b64urlText(JSON.stringify(payload))
  }`;

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${b64url(new Uint8Array(signature))}`;
}

/// RS256, for Google's OAuth token endpoint.
///
/// Google's key is the `private_key` field of a service account JSON file,
/// which is PKCS#8 PEM for an RSA key.
export async function signGoogleJwt(options: {
  clientEmail: string;
  privateKeyPem: string;
  scope: string;
}): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(options.privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: options.clientEmail,
    scope: options.scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 60 * 60,
  };

  const signingInput = `${b64urlText(JSON.stringify(header))}.${
    b64urlText(JSON.stringify(payload))
  }`;

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${b64url(new Uint8Array(signature))}`;
}
