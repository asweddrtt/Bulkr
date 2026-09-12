# Builds supabase\.env from a Firebase service-account JSON.
#
# The private key inside that file is multi-line, which is exactly what a shell
# is worst at: pasting it into `supabase secrets set` mangles it, and a mangled
# key fails later at the point where the function tries to sign a token, with
# an error that says nothing about newlines.
#
# So this reads the JSON directly, converts the key's real line breaks into the
# literal backslash-n sequences the function un-escapes at runtime, and writes
# the file that `supabase secrets set --env-file` wants.
#
# ASCII only, on purpose. Windows PowerShell 5 reads a .ps1 as ANSI unless it
# has a UTF-8 BOM, so a single em dash in a comment turns into three bytes of
# mojibake and takes the parser down with it. Nothing in this file is above
# character 127, and it should stay that way.
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
    # The JSON downloaded from Firebase, Project settings, Service accounts,
    # Generate new private key.
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
        throw "That JSON has no '$field', so it is not a service-account key. The one you want comes from Firebase, Project settings, Service accounts, Generate new private key."
    }
}

# ConvertFrom-Json has already turned the JSON's escaped newlines into real
# line breaks, so this puts them back. CRLF first: on Windows the file may
# carry both, and replacing the bare newline first would leave a stray carriage
# return inside the key.
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

# ASCII rather than the default: PowerShell 5's Out-File writes UTF-16, and the
# Supabase CLI reads the resulting file as binary noise.
Set-Content -Path $OutFile -Value $lines -Encoding ascii

Write-Host ""
Write-Host "Wrote $OutFile with 4 secrets."
Write-Host ""
Write-Host "Next, run these two:"
Write-Host "  supabase functions deploy send-push --no-verify-jwt"
Write-Host "  supabase secrets set --env-file $OutFile"
Write-Host ""
Write-Host "Then in the dashboard webhook, set the x-push-secret header to:"
Write-Host "  $secret"
Write-Host ""
