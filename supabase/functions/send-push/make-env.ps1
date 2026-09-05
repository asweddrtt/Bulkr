# Builds supabase\.env from a Firebase service-account JSON.
#
# The private key inside that file is multi-line, which is exactly what a shell
# is worst at: pasting it into `supabase secrets set` mangles it, and a mangled
# key fails at the point where the function tries to sign a token, with an
# error that says nothing about newlines.
#
# So this reads the JSON, converts the key's real line breaks into the literal
# \n sequences the function un-escapes at runtime, and writes the file that
# `supabase secrets set --env-file` wants. Nothing is printed, because the
# whole point is that these values do not go through a terminal.
#
# Usage, from the repo root:
#
#   .\supabase\functions\send-push\make-env.ps1 -ServiceAccount C:\path\to\firebase-service-account.json
#
# Then:
#
#   supabase secrets set --env-file supabase\.env

[CmdletBinding()]
param(
    # The JSON downloaded from Firebase → Project settings → Service accounts.
    [Parameter(Mandatory = $true)]
    [string]$ServiceAccount,

    # Where to write. Already covered by .gitignore at this path.
    [string]$OutFile = "supabase\.env"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ServiceAccount)) {
    throw "No such file: $ServiceAccount"
}

$sa = Get-Content -Raw -Path $ServiceAccount | ConvertFrom-Json

foreach ($field in @("project_id", "client_email", "private_key")) {
    if (-not $sa.$field) {
        throw "$ServiceAccount has no '$field'. That is not a service-account key — the one you want comes from Project settings -> Service accounts -> Generate new private key."
    }
}

# ConvertFrom-Json has already turned the JSON's \n into real line breaks, so
# this puts them back. CRLF first: on Windows the file may carry both, and
# replacing the bare newline first would leave a stray carriage return inside
# the key.
$key = $sa.private_key -replace "`r`n", '\n' -replace "`n", '\n'

# 64 hex characters, without needing openssl on the machine.
$secret = ([guid]::NewGuid().ToString("N")) + ([guid]::NewGuid().ToString("N"))

$lines = @(
    "FCM_PROJECT_ID=$($sa.project_id)",
    "FCM_CLIENT_EMAIL=$($sa.client_email)",
    "FCM_PRIVATE_KEY=`"$key`"",
    "PUSH_WEBHOOK_SECRET=$secret"
)

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# ASCII rather than the default: PowerShell 5 writes UTF-16 from Out-File, and
# the Supabase CLI reads the resulting file as binary noise.
Set-Content -Path $OutFile -Value $lines -Encoding ascii

Write-Host "Wrote $OutFile (4 secrets)."
Write-Host ""
Write-Host "Next:"
Write-Host "  supabase functions deploy send-push --no-verify-jwt"
Write-Host "  supabase secrets set --env-file $OutFile"
Write-Host ""
Write-Host "Then paste this into the webhook's x-push-secret header:"
Write-Host "  $secret"
