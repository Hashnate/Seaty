# Push Notifications

How FCM push works in Seaty, how to set it up, and how to diagnose it when it stops.

Push has broken three times, and each time the symptom was the same: the backend logs
`FCM Push sent successfully` and nothing arrives on the phone. That message means FCM accepted
the request — nothing more. Every failure so far has been upstream of it.

## The delivery chain

A push crosses ten links. **Any link can fail silently**, and most of them do — the layer above
carries on as if nothing happened. Read this list as a checklist; the failure is always at the
lowest link that isn't working.

| # | Link | Fails silently as |
|---|------|-------------------|
| 1 | Firebase project holds an APNs auth key (iOS) | FCM returns `THIRD_PARTY_AUTH_ERROR` |
| 2 | App bundle carries `GoogleService-Info.plist` / `google-services.json` | native Firebase never configures |
| 3 | Native init — `FirebaseApp.configure()` (iOS), google-services Gradle plugin (Android) | `configured=false` |
| 4 | Flutter plugins registered — `GeneratedPluginRegistrant` | every channel answers `channel-error` |
| 5 | **FlutterFire packages are one coherent generation** | **only Firebase channels answer `channel-error`** |
| 6 | Dart `Firebase.initializeApp()` succeeds | `[core/no-app]` on every later call |
| 7 | Notification authorisation granted | iOS accepts the token, then discards every push |
| 8 | APNs device token exists (iOS), then FCM mints a registration token | token is null, or minted undeliverable |
| 9 | Token reaches `POST /notifications/fcm-token` and lands in `users.fcm_token` | no token, no push |
| 10 | Backend `firebase_admin` sends, FCM relays to APNs / Android | *this* is what "sent successfully" covers |

Links 1–9 are all invisible from the backend. That is why the backend log is the *last* place to
look, not the first.

## The rule that keeps breaking

**The FlutterFire packages must be one release generation.**

```yaml
firebase_core: ^4.0.0
firebase_messaging: ^16.0.0
firebase_crashlytics: ^5.0.0
```

`firebase_core`, `firebase_messaging` and `firebase_crashlytics` share
`firebase_core_platform_interface` and `_flutterfire_internals`, and their Pigeon channel
definitions are generated per release. Mix generations and you get a plugin that **compiles,
links, registers, and returns cleanly from `registerWithRegistrar`** — while every call over its
channel fails with:

```
PlatformException(channel-error, Unable to establish connection on channel., null, null)
```

Nothing about that error names the version skew. It reads like a registration bug, and it will
send you hunting through `AppDelegate.swift` for a day.

### How it happened on 2026-08-10

1. `8b1fbe8` added `firebase_crashlytics`
2. `d4887b7` bumped `web_socket_channel` to 3.x *"to resolve firebase_core dependency conflicts"*
3. That lifted the `<3.5` ceiling holding `firebase_core` down
4. `firebase_core` jumped **3.4.0 → 3.15.0**; `firebase_messaging` stayed on **15.1.0** — nine
   months apart

`pubspec.lock` is committed, so CI baked the skewed set into every build for two weeks.

**When changing any Firebase package, change all three, and check the resolved versions in
`pubspec.lock` — not just the constraints in `pubspec.yaml`.**

## Setup

### Firebase console

- APNs **auth key** (`.p8`) uploaded under Project Settings → Cloud Messaging → iOS app.
  Without it every iOS send returns `THIRD_PARTY_AUTH_ERROR`.
- iOS bundle ID and Android package name both `lk.seaty.app`.

### iOS

| File | Must contain |
|------|--------------|
| `ios/Runner/GoogleService-Info.plist` | `GCM_SENDER_ID`, `GOOGLE_APP_ID`, `BUNDLE_ID`, `API_KEY` |
| `ios/Runner/Runner.entitlements` | `aps-environment` = `production` (App Store / TestFlight) or `development` (Xcode run) |
| `ios/Runner/Info.plist` | `UIBackgroundModes` includes `remote-notification` |
| `ios/Runner/AppDelegate.swift` | `FirebaseApp.configure()`, `UNUserNotificationCenter.current().delegate = self`, `application.registerForRemoteNotifications()`, and the `didRegisterForRemoteNotificationsWithDeviceToken` → `Messaging.messaging().apnsToken` mapping |

`aps-environment` must match how the build is signed. A development-signed build registers a
**sandbox** APNs token; if the entitlement says `production`, APNs drops every push with no error
reaching FCM.

### Android

| File | Must contain |
|------|--------------|
| `android/app/google-services.json` | `project_number`, `mobilesdk_app_id`, `api_key`, package `lk.seaty.app` |
| `android/app/build.gradle.kts` | `com.google.gms.google-services` and `com.google.firebase.crashlytics` plugins |
| `android/settings.gradle.kts` | the same two plugins declared with versions, `apply false` |
| `AndroidManifest.xml` | `android.permission.POST_NOTIFICATIONS` (required at runtime from API 33) |

### Backend

| Item | Where |
|------|-------|
| Service account JSON | `backend/firebase-service-account.json` — gitignored, mounted read-only |
| Env var | `GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json` |
| Mount | `docker-compose.yml` → `./backend/firebase-service-account.json:/app/firebase-service-account.json:ro` |
| Send path | `send_fcm_push()` in `app/routes/notifications.py` |

`send_fcm_push` is blocking. Call it with `await run_in_threadpool(...)` from any `async def` —
see the threadpool rule in CLAUDE.md.

### Database

`users.fcm_token` must exist in **both** `backend/schema.sql` and `backend/migrate_db.py`. It was
missing from the migration until 2026-08-25, so any database created before the column was added
silently lacked it.

### CI

`.github/workflows/mobile-release.yml`:

- **Flutter is pinned** (`flutter-version: '3.47.1'`). Unpinned `channel: stable` moved under us
  once already; a release build must not depend on which day it ran.
- **SPM is disabled** (`flutter config --no-enable-swift-package-manager`). `firebase_core` ships
  a `Package.swift`, `firebase_messaging` does not; a split resolution leaves the Firebase
  plugins out of `GeneratedPluginRegistrant`.
- **The registrant is verified** — the build greps `GeneratedPluginRegistrant.m` for Firebase and
  fails loudly if it's absent.
- **`flutter analyze --no-fatal-warnings --no-fatal-infos`** runs before the 15-minute archive so
  an API break fails in seconds. Errors only; the tree carries unrelated pre-existing warnings.

TestFlight build number is `github.run_number - BUILD_NUMBER_OFFSET`. Don't change the offset —
it collides with numbers App Store Connect has already accepted.

## Diagnosing

### Instruments

**`POST /api/v1/public/log`** — unauthenticated diagnostic sink. Both Dart and native Swift post
to it; everything lands in the backend log prefixed `[ios-native-log]`. This exists because
`debugPrint` is a no-op in release builds, which is exactly how a dead Firebase went unnoticed in
production for two weeks.

**Build marker** — every Dart diagnostic is stamped `[diag-N/platform]` by `reportDiagnostic()`
in `shared_providers.dart`. Bump `kDiagnosticsRevision` whenever the diagnostics change.
Without it, an old build and a new one report identically and you cannot tell whether a fix
actually shipped.

**Native probes** — `AppDelegate.nativeLog()` reports whether `FirebaseApp.configure()` succeeded
and whether `didInitializeImplicitFlutterEngine` fired. Dart cannot see past a dead channel; once
a channel fails, all Dart knows is that nobody answered.

### Symptom → cause

| Symptom | Cause | Fix |
|---------|-------|-----|
| `[firebase-init-failed] … channel-error` **and** other plugins work | FlutterFire version skew | align all three packages |
| `channel-error` **and** no plugin works | `GeneratedPluginRegistrant` never ran | check `didInitializeImplicitFlutterEngine` fires |
| `[core/no-app]` | `Firebase.initializeApp()` failed earlier and was swallowed | read `[firebase-init-failed]` for the real exception |
| **No permission prompt on first launch** | Firebase isn't up — `requestPermission()` is itself a plugin call | fix init; the prompt is a proxy for a healthy Firebase |
| `[fcm-permission] not granted: denied` | user declined, or app wasn't deleted before reinstall | delete the app to reset iOS to `notDetermined` |
| `[fcm-apns] no APNs token` | APNs registration failing | check entitlement vs signing, and `didFailToRegisterForRemoteNotifications` |
| No `FCM token updated for user …` line at all | registration died before its POST | look one link down the chain |
| `FCM Push sent successfully` but nothing arrives | stale token, or device not authorised | clear tokens, re-register, verify provenance |

**The permission prompt is the cheapest diagnostic you have.** It appears only if Firebase
initialised, so its presence or absence tells you within five seconds of first launch which half
of the chain to investigate — no logs required.

### Verification procedure

```bash
# 1. Clear stale tokens so the result is unambiguous
docker compose exec -T db psql -U postgres -d seaty \
  -c "UPDATE users SET fcm_token = NULL WHERE fcm_token IS NOT NULL;"

# 2. Install, launch, sign in. Then watch:
docker compose logs -f backend | \
  grep -E "native\]|firebase-init|fcm-permission|fcm-apns|FCM token updated|FCM Push sent"
```

A healthy launch looks like this:

```
[native] didFinishLaunching configured=true
[native] didInitializeImplicitFlutterEngine fired
[native] GeneratedPluginRegistrant.register returned
FCM token updated for user … had_previous=no, new_token=…
FCM Push sent successfully: projects/seaty-3db21/messages/…
```

What matters is what's **absent**: no `[firebase-init-failed]`, no `[fcm-permission] not granted`.

### Confirming which build a token came from

FCM records the app version that minted a token:

```python
# scopes: https://www.googleapis.com/auth/firebase.messaging
GET https://iid.googleapis.com/iid/info/<TOKEN>?details=true
```

Returns `applicationVersion`, `application`, `platform`. If it reports an older version than
`pubspec.yaml`, the token predates the build you think you're testing. This is how we proved the
stored tokens were stale.

Note: `apnsTokens` is **not** a documented field of that response. Its absence proves nothing.

## Traps

**`users.fcm_token` is a single column.** One device per user — a second device overwrites the
first, so only the most recent install can receive push. Multi-device support needs a separate
`user_devices` table.

**`users.updated_at` is trigger-maintained.** `update_users_updated_at` fires `BEFORE UPDATE` on
every row change, including the `token_version` bump at login. **A moving `updated_at` is not
evidence of a token write.** Compare the token value, or look for the `FCM token updated` log
line.

**FCM accepting a message proves almost nothing.** `messaging.send()` returns a message ID once
FCM has queued it. APNs rejections happen afterwards and never reach the caller. A valid,
registered token belonging to an unauthorised device will accept every push and display none.

**`getToken()` does not require notification permission on iOS.** It needs only an APNs device
token, which `registerForRemoteNotifications()` provides regardless of authorisation. So an app
that was never granted permission still produces a perfectly valid FCM token — which is worse
than no token, because the backend then logs "sent successfully" forever. `registerFcmToken()`
therefore refuses to register unless authorisation is granted.

**Dry-run sends validate the token.** `messaging.send(msg, dry_run=True)` returns `UNREGISTERED`
for a dead token without delivering anything — safe way to check a token is live.

**Deleting the app resets iOS notification permission.** iOS prompts once per install; if the app
sits in `denied`, `requestPermission()` returns immediately without prompting. Delete before
reinstalling when testing the prompt.

## Related

- `mobile/lib/providers/shared_providers.dart` — init, permission, token registration, diagnostics
- `mobile/ios/Runner/AppDelegate.swift` — native config, APNs mapping, probes
- `backend/app/routes/notifications.py` — `send_fcm_push`, `create_and_send_notification`, `/fcm-token`
- [CLAUDE.md](../CLAUDE.md) — threadpool rule for blocking I/O in `async def`
