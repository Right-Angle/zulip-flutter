# Right Angle "Chat" — self-hosted E2EE push notifications

This fork of `zulip-flutter` ("Chat", package `dev.rightangle.chat`) plus
our self-hosted Zulip server deliver mobile push notifications through
**our own Firebase Cloud Messaging project**, with payloads
**end-to-end encrypted** — Google's FCM carries only ciphertext.
No Zulip push-service plan is involved.

How: our server runs Zulip's bouncer component (**zilencer**) itself and
sends directly to FCM with our own credentials. The app encrypts its push
registration to *our* server's bouncer key, and each notification payload
is encrypted to a per-device key. This mirrors how Zulip 12's E2EE
notifications work through push.zulipchat.com — minus the third party.

```text
Chat app (dev.rightangle.chat)
  │  registration: sealed to OUR bouncer public key
  ▼
chat.rightangle.dev  (Zulip 12.1, git deploy, zilencer enabled)
  │  payload: XSalsa20-Poly1305, encrypted to the device's push key
  ▼
FCM project sid-personal (ciphertext only)  →  device decrypts & displays
```

## Component inventory

| Piece | Value / location |
| --- | --- |
| App package | `dev.rightangle.chat` (label "Chat") |
| Fork repo | `Right-Angle/zulip-flutter`, branch `rightangle-chat`; upstream `zulip/zulip-flutter` |
| Fork delta marker | grep for `RA-fork` in `lib/`; plus `android/`+`ios/` identity, icons, `tools/generate-logos`, `docs/rightangle/` |
| Firebase project | `sid-personal` (number `386885828342`), Android app id `1:386885828342:android:359191414dc129474f76d7` |
| Server | `chat.rightangle.dev` — DigitalOcean droplet `zulip-ra` (139.59.32.151), Ubuntu 22.04, PostgreSQL 14, 2 GB RAM + 2 GB swap |
| Deployment method | **git** (`upgrade-zulip-from-git`) — REQUIRED, see below |

## Secrets inventory

| Secret | Lives at | Backed up via | Rotation |
| --- | --- | --- | --- |
| FCM service-account key | server `/etc/zulip/firebase-admin.json` (600, zulip) | GCP Secret Manager: `firebase-admin-chat` in `sid-personal` | `gcloud iam service-accounts keys create` → new Secret Manager version → replace on server → delete old key id |
| E2EE bouncer keypair(s) | server `/etc/zulip/zulip-secrets.conf`, key `push_registration_encryption_keys` (JSON map public→private) | `manage.py backup` (includes `/etc/zulip`) **and** GCP Secret Manager: `e2ee-push-keys-chat` in `sid-personal` | see "Rotating the E2EE key" below; after rotating, update the Secret Manager copy: `ssh root@chat.rightangle.dev "grep '^push_registration_encryption_keys' /etc/zulip/zulip-secrets.conf \| cut -d' ' -f3-" \| gcloud secrets versions add e2ee-push-keys-chat --data-file=-` |
| APNs placeholder | `/etc/zulip/apns-placeholder.p8` (empty file) | n/a — recreate with `touch` | replace with a real APNs key if iOS ever ships |

The app embeds only **public** material (Firebase client config in
`lib/firebase_options.dart`, bouncer *public* key in
`lib/model/push_device.dart`) — safe to commit, by design.

## Server configuration (as deployed)

`/etc/zulip/settings.py`:

```python
# Legacy bouncer line COMMENTED OUT — if this is ever re-enabled,
# computed_settings force-flips ZULIP_SERVICE_PUSH_NOTIFICATIONS back to True.
#PUSH_NOTIFICATION_BOUNCER_URL = 'https://push.zulipchat.com'

ZULIP_SERVICE_PUSH_NOTIFICATIONS = False
ANDROID_FCM_CREDENTIALS_PATH = "/etc/zulip/firebase-admin.json"
APNS_TOKEN_KEY_FILE = "/etc/zulip/apns-placeholder.p8"  # Android-only workaround; never read

# E2EE: run our own bouncer. zilencer imports corporate, so both are needed.
EXTRA_INSTALLED_APPS = ["analytics", "zilencer", "corporate"]
```

Also deployed:

- `/etc/nginx/zulip-include/app.d/rightangle-deny-remotes.conf` — returns
  403 on `/api/v1/remotes/` so strangers can't use us as a public bouncer.
- Realm setting `require_e2ee_push_notifications` — enabled once the fleet
  is on the Chat app; guarantees no plaintext notification is ever sent.

Notes:

- `ANDROID_FCM_CREDENTIALS_PATH` is read **at import** — a missing/bad file
  prevents the server from booting. Validate before restarting (below).
- The APNs placeholder satisfies `push_notifications_configured()`, which
  requires both APNs and FCM settings to be non-None in production. It is
  never opened while no iOS device exists.

---

## ⚠ Server upgrade playbook (read before every upgrade)

**Rule 1 — git deployments only.** Release **tarballs do not contain
zilencer/corporate**. If this server is ever upgraded with
`upgrade-zulip <tarball>`, Django will fail to boot (EXTRA_INSTALLED_APPS
references missing modules) and push breaks. Always:

```bash
/home/zulip/deployments/current/scripts/upgrade-zulip-from-git <tag>   # e.g. 12.2, 13.0
```

**Rule 2 — this box has 2 GB RAM.** Per the official upgrade docs, stop
the server first so webpack doesn't OOM (adds downtime, prevents failure):

```bash
su zulip -c '/home/zulip/deployments/current/scripts/stop-server'
```

**Full sequence:**

```bash
# 1. Backup (DB + /etc/zulip incl. both push secrets; uploads excluded)
su zulip -s /bin/bash -c 'cd /home/zulip/deployments/current && \
  ./manage.py backup --skip-uploads --output /home/zulip/preupgrade-$(date +%F).tar.gz'

# 2. Read the release's upgrade notes:
#    https://zulip.readthedocs.io/en/stable/overview/changelog.html

# 3. Stop server (Rule 2), then upgrade from git (Rule 1)
su zulip -c '/home/zulip/deployments/current/scripts/stop-server'
/home/zulip/deployments/current/scripts/upgrade-zulip-from-git <tag>

# 4. Verify — ALL FIVE, every time:
curl -s https://chat.rightangle.dev/api/v1/server_settings | grep -o '"push_notifications_enabled":[a-z]*'   # true
curl -s -o /dev/null -w '%{http_code}\n' https://chat.rightangle.dev/api/v1/remotes/server/register          # 403
su zulip -s /bin/bash -c 'cd /home/zulip/deployments/current && ./manage.py shell -c \
  "from django.conf import settings; from zerver.lib.push_notifications import *; \
   print(settings.ZILENCER_ENABLED, sends_notifications_directly(), push_notifications_configured())"'        # True True True
tail -n 30 /var/log/zulip/errors.log    # no tracebacks
# 5. Send yourself a DM from another account with the app backgrounded
#    → notification must arrive.
```

If the nginx deny rule disappears after an upgrade (puppet changes), the
403 check above catches it — recreate the file from this doc.

**Rollback:** previous deployments stay under `/home/zulip/deployments/`;
same-major rollback = restart from the prior directory. Cross-major
rollback requires the backup (restore onto the same Zulip+PostgreSQL
versions it was taken from).

---

## 📱 Client (fork) upgrade playbook

The fork's delta is deliberately tiny. To take an upstream release:

```bash
git fetch upstream
git rebase <upstream-tag-or-main> rightangle-chat
# resolve conflicts, if any — our whole delta:
#   android/app/build.gradle              (applicationId)
#   android/app/src/main/AndroidManifest.xml  (label)
#   ios/Runner/Info.plist                 (display name)
#   assets/app-icons/*                    (Right Angle SVG sources + login PNG)
#   android res icons + ios AppIcon       (regenerate: tools/generate-logos)
#   tools/generate-logos                  (renders our marks)
#   lib/firebase_options.dart             (sid-personal Firebase config)
#   lib/model/push_device.dart            (bouncerPublicKey — RA-fork)
#   lib/widgets/login.dart                (preset URL + logo — RA-fork)
#   pubspec.yaml                          (login PNG asset — RA-fork)
#   docs/rightangle/                      (this doc)
flutter analyze --no-pub && flutter test --no-pub
flutter build apk --release   # sign per release process
# distribute (Play Store rollout, or APK)
```

**Watch these two files during rebases** — if upstream touches them,
re-check our edits still apply cleanly:
- `lib/model/push_device.dart` (registration/E2EE logic evolves here)
- `lib/firebase_options.dart`

**Server-version gates:** the app's E2EE path activates at server
feature level ≥ 468 (Zulip 12); our server is past it. If upstream ever
*requires* a newer server than ours, upgrade the server first (playbook
above), then the app.

---

## Rotating the E2EE bouncer key

Rotation requires coordinating server + app (the app pins one public key):

```bash
# 1. On the server — ADD a new keypair (old ones stay valid):
su zulip -s /bin/bash -c 'cd /home/zulip/deployments/current && \
  ./manage.py manage_push_registration_encryption_keys --add'   # note the new Public key
su zulip -c '/home/zulip/deployments/current/scripts/restart-server'

# 2. In the fork — put the new public key in lib/model/push_device.dart,
#    rebuild, distribute. Devices re-register against the new key
#    on their next app upgrade + launch.

# 3. After the fleet has upgraded (allow weeks), remove the old key:
su zulip -s /bin/bash -c 'cd /home/zulip/deployments/current && \
  ./manage.py manage_push_registration_encryption_keys --remove-key <OLD_PUBLIC_KEY>'
```

## Rebuilding the server from scratch

1. Provision Ubuntu LTS + PostgreSQL matching the backup's versions.
2. Install Zulip **from git at the same version** as the backup.
3. `restore-backup` the latest backup tarball — this brings back the DB,
   `/etc/zulip/settings.py`, `zulip-secrets.conf` (E2EE private keys) —
   push registrations survive.
   If the backup predates the current E2EE key (or only the DB survived),
   restore the keymap from Secret Manager instead — write it as the
   `push_registration_encryption_keys` value in `zulip-secrets.conf`:
   `gcloud secrets versions access latest --secret=e2ee-push-keys-chat --project=sid-personal`
4. Restore the FCM key if needed:
   `gcloud secrets versions access latest --secret=firebase-admin-chat --project=sid-personal > /etc/zulip/firebase-admin.json`
   then `chown zulip:zulip` + `chmod 600`.
5. Recreate `/etc/zulip/apns-placeholder.p8` (`touch` + chown) and the
   nginx deny rule; run the five verification checks.

## Constraints

- **Official Zulip apps get no notifications from this server** — their
  tokens belong to Zulip's Firebase/APNs apps. Everyone uses "Chat".
- **No iOS until**: an iOS app is registered in `sid-personal`, a real
  APNs key replaces the placeholder, and the fork gets an iOS bundle ID.
- The `corporate` app is enabled only because zilencer imports it; with no
  Stripe configuration it is inert. The `/api/v1/remotes/` 403 keeps the
  bouncer surface private either way.
