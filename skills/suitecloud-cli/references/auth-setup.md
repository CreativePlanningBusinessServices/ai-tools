# Authenticate SuiteCloud CLI for an account netsuite-cli already knows

Goal: an unattended, certificate-based ("machine-to-machine", M2M) SuiteCloud auth id for the
same NetSuite account and user that a `netsuite-cli` alias already uses, without a browser.
Verified end to end on a sandbox with SuiteCloud CLI 4.1.1 (2026-10).

## What you need

| Value | Where it comes from |
|---|---|
| Account id (`1234567`, sandboxes `1234567_SB1`…) | `netsuite-cli account list` → `accountId` of the alias |
| Entity (user) id and role id to map | `netsuite-cli account cert list --account <alias>` → `entity.id`, `role.id` of the active certificate (M2M aliases); for auth-code aliases the ids are in netsuite-cli's `config.toml` |
| SuiteCloud's own OAuth client id | constant, public (it is in every SuiteCloud login URL): `6da57bf05a6247fc876c6d228184ff487760a382a43ac7e93eaff743803d22ac` |
| A passkey for the SuiteCloud credential store | you choose it: 32–100 letters and digits; keep it like a password |
| A fresh RSA key pair | generated below; SuiteCloud rejects EC keys and netsuite-cli's certificate cannot be reused |

Why a new key pair: SuiteCloud authenticates as NetSuite's system application **SuiteCloud
Development Integration**, and NetSuite maps each certificate to exactly one application + entity +
role. netsuite-cli's certificate is mapped to netsuite-cli's own integration, so a second
certificate is needed. The SDK also accepts only RSA private keys ("There was an error with the
private key" for EC keys), while netsuite-cli generates EC P-256 by default.

## Execution context (read first)

SuiteCloud keeps two separate credential stores and picks one from the environment:

| `SUITECLOUD_CI` | `SUITECLOUD_CI_PASSKEY` | What works |
|---|---|---|
| `1` | set | certificate auth ids (`credentials_ci.p12`) and every command; browser login refused |
| unset | unset | browser auth ids only; a certificate auth id is "not available" |
| unset | set | only `account:setup:ci` |

So for unattended use, export **both** persistently and open a new shell before continuing:

```bash
# macOS / Linux: generate a 48-character passkey and append both exports to the profile without displaying it
printf 'export SUITECLOUD_CI_PASSKEY=%s\nexport SUITECLOUD_CI=1\n' "$(openssl rand -hex 24)" >> ~/.zshrc
# optional helper for the rare browser login
printf 'nsbrowser() { env -u SUITECLOUD_CI -u SUITECLOUD_CI_PASSKEY "$@"; }\n' >> ~/.zshrc   # usage: nsbrowser suitecloud account:setup
```

```powershell
# Windows: user environment variables; new terminals pick them up. The passkey is generated, never typed or shown.
[Environment]::SetEnvironmentVariable("SUITECLOUD_CI_PASSKEY", (-join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })), "User")
[Environment]::SetEnvironmentVariable("SUITECLOUD_CI", "1", "User")
# for a one-off browser login in the current window only:
Remove-Item Env:SUITECLOUD_CI, Env:SUITECLOUD_CI_PASSKEY -ErrorAction SilentlyContinue; suitecloud account:setup
```

The passkey is the only thing protecting `credentials_ci.p12`, and it needs no human to know it:
never `echo $SUITECLOUD_CI_PASSKEY`, `cat ~/.zshrc`, `Get-ChildItem Env:` or otherwise print it. If
it is ever lost, delete `credentials_ci.p12`, generate a new one and redo step 5 for each auth id.

## Steps

### 1. Does an auth id already exist?

```
netsuite-cli account list
suitecloud account:manageauth --list
```

If the list already has an auth id for that account id, select it in the project and stop:
`suitecloud account:setup:ci --select <authid>`. Otherwise continue.

If `netsuite-cli account list` has no alias for the account, this recipe has nothing to start
from: create an M2M alias first with the netsuite-cli skill's "Bootstrap" (one browser login to
that account, then `cert generate` → `cert upload` → `account add --flow m2m`). An alias for a
different account, including the production a sandbox was copied from, cannot be used.

### 2. Entity and role

```
netsuite-cli account cert list --account <alias> --pretty
```

Take `entity.id` and `role.id` from the active (not revoked) certificate. They identify the same
user and role netsuite-cli acts as; the SuiteCloud mapping will use them too.

### 3. Generate the RSA key pair

Keep the key outside any repository and never upload it; only the certificate goes to NetSuite.

```bash
# macOS / Linux
mkdir -p ~/.suitecloud-sdk/keys/<ACCOUNT_ID> && cd ~/.suitecloud-sdk/keys/<ACCOUNT_ID>
openssl req -x509 -newkey rsa:4096 -sha256 -days 730 -nodes -subj "/CN=suitecloud-m2m" -keyout suitecloud-key.pem -out suitecloud-cert.pem
chmod 600 suitecloud-key.pem
```

```powershell
# Windows (openssl ships with Git for Windows; not yet run on Windows — report what you see)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.suitecloud-sdk\keys\<ACCOUNT_ID>" | Out-Null
Set-Location "$env:USERPROFILE\.suitecloud-sdk\keys\<ACCOUNT_ID>"
& "C:\Program Files\Git\usr\bin\openssl.exe" req -x509 -newkey rsa:4096 -sha256 -days 730 -nodes -subj "/CN=suitecloud-m2m" -keyout suitecloud-key.pem -out suitecloud-cert.pem
```

730 days is NetSuite's maximum validity. The key file starts with `-----BEGIN PRIVATE KEY-----`.

### 4. Map the certificate to SuiteCloud Development Integration

netsuite-cli's certificate command talks to NetSuite's certificate API; pointing it at
SuiteCloud's client id creates the mapping the UI's "OAuth 2.0 Client Credentials (M2M) Setup"
page would:

```
netsuite-cli account cert upload --account <alias> --cert suitecloud-cert.pem --client-id 6da57bf05a6247fc876c6d228184ff487760a382a43ac7e93eaff743803d22ac --entity <entity.id> --role <role.id>
```

The response's `certificateId` is the value for the next step (`details.application_id` is the
SuiteCloud Development Integration record). The calling role needs the permission
*Manage own OAuth 2.0 Client Credentials certificates* (Administrator has it); a 403 means it is
missing. NetSuite allows **five active certificates per integration record**, and every SuiteCloud
M2M user in the account shares this one integration: check with
`netsuite-cli account cert list --account <alias> --client-id <the client id above>` and revoke
stale ones before adding a sixth. That list answers HTTP 500 while nothing is mapped yet (Edge
cases); upload anyway.

Alternative (no API access): Setup > Integration > Manage Authentication > OAuth 2.0 Client
Credentials (M2M) Setup (`/app/oauth2/clientcredentials/setup.nl`) > Create New: Entity = the user,
Role = the role, Application = *SuiteCloud Development Integration*, Certificate = the `.pem`,
Save. The new row shows the Certificate ID. If *SuiteCloud Development Integration* is not in the
Application list, the account has never had a SuiteCloud login: one browser-based
`suitecloud account:setup` by any user creates it.

### 5. Create the auth id

With `SUITECLOUD_CI=1` and the passkey exported (section above), inside any SuiteCloud project:

```
suitecloud account:setup:ci --account <ACCOUNT_ID> --authid <ACCOUNT_ID>_M2M --certificateid <certificateId> --privatekeypath <absolute path>/suitecloud-key.pem
```

Expected: "The authentication was successful with the following account and role: … This project
will use the authentication ID "<ACCOUNT_ID>_M2M" as default." Sandboxes resolve without
`--domain`; pass it only for a custom NetSuite domain. Windows paths may use forward slashes
(`C:/Users/me/.suitecloud-sdk/keys/1234567/suitecloud-key.pem`).

### 6. Verify

```
suitecloud account:manageauth --list
suitecloud object:list --type customlist
netsuite-cli suiteql --account <alias> --pretty "SELECT TO_CHAR(date,'HH24:MI') AS at, oauthappname, requesturi, status FROM LoginAudit WHERE date >= SYSDATE - 0.01 ORDER BY date DESC FETCH FIRST 5 ROWS ONLY"
```

The audit rows show `oauthappname = SuiteCloud Development Integration` with `status = Success`
for `/services/rest/auth/oauth2/v1/token` and `/app/ide/ide.nl`. `object:list` needs a project
with a `deploy.xml` (4.x reports "Invalid SuiteCloud project context" otherwise).

## Edge cases

- **"error with the certificate ID … not valid or expired or revoked"**: the certificate is mapped
  to the wrong application (must be SuiteCloud Development Integration), revoked, or the mapping
  was wiped by a sandbox refresh. Mappings are per account and are not copied to sandboxes;
  redo steps 3–5 after every refresh.
- **"error with the private key"**: not an RSA key, or not the key of that certificate.
- **`cert list --client-id <SuiteCloud id>` returns HTTP 500 "Internal Error"**: seen on a sandbox
  whose SuiteCloud Development Integration record existed but had no certificate mapped to it yet.
  It does not mean the record is missing: run the `cert upload` of step 4, after which the same
  list works.
- **The account has never had a SuiteCloud login** (no SuiteCloud Development Integration record):
  the Setup page's Application list lacks *SuiteCloud Development Integration* (observed symptom), and
  `cert upload` is expected to reject the client id (not yet observed; report the exact error).
  `netsuite-cli suiteql --account <alias> "SELECT COUNT(*) AS logins FROM LoginAudit WHERE oauthappname = 'SuiteCloud Development Integration'"`
  above zero shows the record exists. One browser-based `suitecloud account:setup` by any user,
  with the CI variables unset, creates the record; then redo step 4.
- **"authentication ID is not available"** right after a successful setup: you are in the other
  execution context (variables unset). Certificate auth ids are invisible without them.
- **Rotation**: upload the replacement first (step 4), run step 5 with the new certificate id and
  the same auth id, then `netsuite-cli account cert revoke <old id> --account <alias> --client-id <SuiteCloud client id>`.
- **Removing**: `suitecloud account:manageauth --remove <authid>` only forgets it locally; revoke
  the certificate as above to disable it in NetSuite.
- **CI pipelines**: copy `~/.suitecloud-sdk/credentials_ci.p12` to the runner and set the same two
  variables there; or run step 5 on the runner with the key injected as a secret. Changing the
  passkey invalidates the file.
