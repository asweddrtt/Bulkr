# moderate-image

Decides whether a picked photo may be uploaded, using AWS Rekognition's
`DetectModerationLabels`. Called by `ImageUploader` and `UserRepository` before
a single byte is written to a bucket, so a refused image never reaches a public
URL.

## What this replaced, and why

An on-device model that did not work on either platform:

- **iOS** scored a full frontal nude *below* a topless photo. The model is
  OpenNSFW2, converted to Core ML; it declares RGB input but bakes in
  open_nsfw's BGR channel means, so the scores were close to noise.
- **Android** never ran it at all. The plugin's Android side needs
  `OpenNSFW2.tflite` downloaded at runtime, and the URL it downloads from
  returns **404** — the other three models on that same release serve fine,
  only the one Bulkr used is missing.

So the app spent a year claiming to filter images while filtering nothing. The
lesson worth keeping: both failures were *silent*, and both were in the
fail-open direction. That is why this function returns a 502 rather than a
cheerful `allow` when it breaks, and why the client counts the failures.

## AWS setup

### 1. An IAM user with exactly one permission

Do not reuse a broader key. This function needs one action and nothing else:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rekognition:DetectModerationLabels",
      "Resource": "*"
    }
  ]
}
```

`DetectModerationLabels` takes inline bytes, so no S3 bucket and no S3
permission is involved. Create the user, attach that policy inline, and take an
access key.

### 2. Secrets

Put them in a file rather than typing them as arguments. A secret on a command
line goes into the shell's history file on disk — PowerShell's PSReadLine keeps
one, and so does bash — where it outlives any care taken over it.

```sh
supabase link --project-ref hqdfaeiyflbbzkduskaz

# .env is already gitignored, so it cannot be committed by accident.
cat > .env <<'ENV'
REKOGNITION_ACCESS_KEY_ID=AKIA...
REKOGNITION_SECRET_ACCESS_KEY=...
REKOGNITION_REGION=us-east-1
ENV

supabase secrets set --env-file .env
rm .env
```

**On Windows / PowerShell**, same idea — and note that `\` is *not* a line
continuation there, which is the thing that bites first. PowerShell uses a
backtick, so a pasted bash command runs each line as a separate program and
answers `... is not recognized as the name of a cmdlet`:

```powershell
supabase link --project-ref hqdfaeiyflbbzkduskaz

@"
REKOGNITION_ACCESS_KEY_ID=AKIA...
REKOGNITION_SECRET_ACCESS_KEY=...
REKOGNITION_REGION=us-east-1
"@ | Out-File -FilePath .env -Encoding ascii

supabase secrets set --env-file .env
Remove-Item .env
```

### If a key is ever exposed

Rotate it rather than reasoning about how bad it was: IAM → the user →
Security credentials → deactivate, delete, create a new one. It takes a minute.
Then clear the shell history that recorded it —
`(Get-PSReadLineOption).HistorySavePath` on Windows, `~/.bash_history` or
`~/.zsh_history` elsewhere.

The one-action policy above is what keeps that a small event: a leaked key can
classify images and nothing else. No S3, no billing, no IAM, no other service.
That is the entire reason not to reuse a broader key here.

Named `REKOGNITION_*` rather than `AWS_*` deliberately — the platform reserves
some prefixes, and these are read explicitly rather than picked up by the SDK's
default credential chain, so there is no ambiguity about where they came from.

**Match the region to the Supabase project, not to your users.** This is the
part that surprises people. The round trip is *edge function → Rekognition*,
so what costs milliseconds is the distance between wherever Supabase runs this
function and wherever Rekognition answers. The user's phone is not in that hop
at all — it already paid its latency getting to Supabase.

The project's region is in the Supabase dashboard under Project Settings →
General. Pick the AWS region closest to it; `us-east-1` is the safe default and
is the region the pricing above is quoted in.

Region is also **where user photos are processed**, which is a data-residency
question if you have EU users, and a sentence the privacy policy has to carry
either way.

### 3. Deploy

```sh
supabase functions deploy moderate-image
```

The caller's JWT is verified by the platform, so only signed-in users reach it.

## Cost

`DetectModerationLabels` is a **Group 2** API: **$0.001 per image**
($1.00 / 1,000) for the first million each month.

The free tier is 1,000 images/month and lasts **12 months from account
creation** — worth a calendar reminder, because it expires rather than
shrinking. New accounts also get up to $200 in Free Tier credits, which at
$1/1,000 is roughly 200,000 images.

One call per uploaded image. Thumbnails are not checked separately — they are
generated from bytes that already passed.

## The policy

In `policy.ts`, deliberately separate from this file so it can be read and
argued with on its own, and tested without AWS:

```sh
node --experimental-strip-types supabase/functions/moderate-image/policy.test.ts
```

The part worth understanding before changing it: **the hard problem here is not
catching nudes.** Any modern model does that. It is not rejecting a shirtless
progress photo, which is the best content on the platform. So the policy has
two halves —

- `REFUSE` — named labels with the confidence each needs
- `NEVER_REFUSE` — labels that must never reject, whatever their confidence

`Emaciated Bodies` is in the second list on purpose. Rekognition files it under
"Visually Disturbing", and a bodybuilder at low body fat is exactly what it
fires on. Rejecting somebody's cutting photo as disturbing would be wrong and
insulting.

There is also a backstop: an *unrecognised* label whose parent is a refused
category is refused at 0.9. Rekognition renames labels between taxonomy
versions, and a policy matching only exact names fails open when that
happens — new label, no match, everything allowed. Which is the same shape as
the bug this whole function replaced.

## Watching it

The app records three things (never the image, never a URL):

| Event | Meaning |
|---|---|
| `image_refused` | `variant` carries the label, `score` its confidence |
| `image_allowed` | `variant` is `clean` or `reviewed` |
| `image_check_skipped` | **the one to watch** — an upload went through unchecked |

`image_check_skipped` should be near zero. Anything else means the function is
down, undeployed, or the key is wrong, and uploads are passing unmoderated.

## Reading the logs

`supabase functions logs moderate-image`, while posting a photo from the app.
Deploying is not the same as working, and because the client fails open a
broken setup looks exactly like a working one from the app's side — the photo
uploads either way. So the log is the only place the difference shows.

| What the log says | What it means |
|---|---|
| `{"verdict":"allow",...}` | working |
| `{"verdict":"refuse","reason":"Exposed Male Genitalia",...}` | working, and correctly |
| `REKOGNITION_ACCESS_KEY_ID / ... are not set` | `supabase secrets set` did not take, or the names are misspelled |
| `UnrecognizedClientException` / `InvalidSignatureException` | the key or secret is wrong — a truncated paste does this |
| `AccessDeniedException ... rekognition:DetectModerationLabels` | the key is real but the IAM policy is missing or did not attach |
| `Could not resolve endpoint` / region errors | `REKOGNITION_REGION` is not a region Rekognition serves |
| nothing at all | the app is not reaching the function — check it is a build from this branch |

The last row is the one to check first. An old build has no
`ModerationService` in it, so it will never call this and the log will stay
silent no matter how correct the deploy was.

## Known limit

This is called *by the client*, so a patched client can skip it. The AWS key is
safe and the model is good, but the decision is still advisory.

Closing that means the function doing the upload itself, with the buckets
locked to service-role writes so a client cannot write at all. That is a bigger
change — the function would take the bytes and return the URLs — and is the
natural next slice.
