# DueDesk

**Never miss what is due.**

A focused Flutter application for business deadlines, compliance, renewals, ownership, and supporting evidence. Android and iOS are the primary targets; the source also includes a web target for development and future deployment.

## Toolchain

Built with **Flutter 3.47.6 stable / Dart 3.13.5**. Use this version or a compatible newer stable release. The lockfile is included for reproducible dependencies.

Prerequisites:

- Flutter SDK on `PATH`; run `flutter doctor`.
- Android SDK, accepted Android licences, and JDK 21 for Android builds. The Flutter Gradle integration resolves the required Android platform, NDK, and CMake components.
- macOS, Xcode, and an Apple development team for iOS device signing. This Linux workspace cannot compile or sign iOS.
- An Android emulator/device or an iOS simulator/device.

## Run

From this directory:

```bash
flutter pub get
flutter run
```

The default environment is `demo`. No server, Firebase project, account, or API key is needed.

In the supplied cloud workspace, Flutter is installed at `/workspace/.tooling/flutter/bin`:

```bash
export PATH="/workspace/.tooling/flutter/bin:$PATH"
cd /workspace/mobile
flutter pub get
flutter run
```

Use `flutter devices` to select a connected target. For browser development:

```bash
flutter run -d chrome
# Or: flutter run -d web-server --web-port 8080
```

## Demo

Choose **Continue in demo mode** on the welcome screen, or sign in with:

- Email: `demo@duedesk.app`
- Password: `demo123`

These credentials are strictly local demo credentials. The main demo user has Owner access in REALOFFICE, Admin access in OSWORKS, and Member access in Rootd Consulting, allowing role and organisation isolation to be demonstrated.

Demo records are seeded on the first launch with dates relative to the current day. This keeps overdue, today, soon, upcoming, and completed states visible. Subsequent launches preserve edits, documents, history, and completion dates; dates are not silently reseeded.

Local registration creates an empty company and account. Registered demo users can sign back in with their chosen credentials. Demo password verifiers use the `cryptography` package's PBKDF2-HMAC-SHA256 with independent random salts; passwords are not saved in plaintext. Demo authentication is a simulation, not production identity management.

Demo invitations and password-reset requests do **not** send email. The notification centre is an in-app demo inbox. Reminder preferences are saved; push/email scheduling and delivery belong to the production notification service.

## Implemented flows

- Splash, welcome, login, show/hide password, remembered or session-only login, registration, forgot-password confirmation, onboarding, and logout.
- Repository-derived dashboard counts, attention review, quick actions, nearest deadlines, and completion history.
- DueItem creation, editing, assignment, debounced search, sorting, combined filters, archive, progress, notes, and auditable completion.
- Weekly, monthly, quarterly, half-yearly, yearly, and custom-day recurrence. Completion and renewal preserve the previous record and generate a separate successor; repeated completion cannot duplicate the next item.
- Month calendar with date markers, selected-day obligations, and grouped agenda.
- Evidence selection and upload with mandatory association, size/type validation, progress, PDF/image/text preview, download, replacement, and permission-aware removal. Word documents download for opening in another app. Demo bytes persist locally.
- Live notification bar, reminder engine, notification centre with filters and swipe-to-read, unread state, mark-all-read, and navigation to the relevant obligation.
- App lock with passcode and Face ID / Touch ID, auto-lock, encrypted device storage, app-switcher privacy cover, Android screenshot blocking and sign-in throttling.
- Organisation switching, scoped roles, company settings, logo, team invitations/access changes, category creation/edit/deactivation, profile and avatar, activity, security information, and notification preferences.
- System/light/dark appearance with persistence, responsive tablet grids, flat paper-like surfaces, accessible labels, loading skeletons, empty/error states, refresh, and offline banners.

## Design

A calm, paper-like interface in the spirit of the Claude app, identical on iOS and Android:

- **Warm palette.** Ivory pages (warm charcoal in dark mode), white cards, a single clay accent (`#C6613F`) and ink-coloured text. Tokens live in `AppColors`/`AppSizes` (`lib/core/theme/app_theme.dart`).
- **Flat surfaces with crisp edges.** Hairline borders instead of shadows or blur; corners stay modest (6–10 px), with no pill shapes or glass effects.
- **Serif headings** (Noto Serif) over Inter body text.
- **Hand-drawn illustrations** in ink, sand, clay and sage (`assets/illustrations/`) for the welcome screen, onboarding, empty states, the lock screen, the privacy cover and Security.
- A plain bottom bar on phones and a side rail on tablets.

## Live notifications

- **Notification bar.** New reminders drop in from the top as a banner. Tap to open the obligation (or the inbox when several arrive), swipe up to dismiss; it hides after five seconds. Toggle it under *Notification settings → Live notification bar*.
- **Reminder engine.** With device storage, `remindersDue` (`lib/features/notifications/domain/reminders.dart`) raises a reminder as each obligation crosses a threshold in its reminder schedule (for example 7, 3, 1 and 0 days before) and when it becomes overdue. Each reminder is raised once, survives restarts and respects the *Overdue alerts* setting. Checks run when the workspace opens, every minute, on resume and after unlocking.
- **Server mode** refreshes the workspace each minute while online; the server schedules reminders, and teammates' changes surface in the banner. Your own actions are not announced back to you.
- **Notification centre** with All/Unread filters, Today/Yesterday/Earlier groups, type icons, relative times and swipe-left to mark read.

## Security

- **Encryption at rest.** With device storage, the workspace file and every attachment are encrypted with AES-256-GCM (`lib/core/storage/storage_cipher.dart`). The key is random per installation and kept in the Keychain / Android Keystore-backed secure storage, never beside the data. Files from earlier versions are read once and encrypted on their next save. The offline copy of server data is an encrypted Hive box; the old unencrypted cache is deleted. (On the web, storage is unchanged: a browser would have to keep the key beside the data.)
- **App lock.** Optional six-digit passcode, stored only as a salted PBKDF2-SHA256 verifier in secure storage. Trivial codes (`111111`, `123456`) are refused. A cold start always asks; after leaving the app choose *Immediately*, 1, 5 or 15 minutes (default 1). It also locks after 5 minutes without a touch.
- **Face ID / Touch ID / fingerprint** unlock via `local_auth`, confirmed once before it is enabled; the passcode remains the fallback.
- **Brute-force protection.** After five wrong passcodes, attempts back off exponentially (30 s, 1 min, 2 min…); the tenth signs the account out and forgets the passcode. Sign-in is throttled the same way per email address on this device.
- **Privacy cover.** An opaque cover hides content whenever DueDesk is inactive, so app-switcher snapshots never show obligations or evidence.
- **Block screenshots (Android).** Optional `FLAG_SECURE` also blocks screen recording and recent-apps previews. iOS does not allow apps to block screenshots.
- **Keychain hardening.** Secrets use `first_unlock_this_device`, so they are never restored onto another device from a backup. Signing out, or a fresh password sign-in, removes the passcode.
- Constant-time verifier comparison and a password strength meter on sign-up.

Platform setup is included: `NSFaceIDUsageDescription` (iOS); `FlutterFragmentActivity`, `USE_BIOMETRIC` and the `app.duedesk/security` channel in `MainActivity.kt` (Android). On Android 8 and earlier, `local_auth` also recommends an AppCompat `LaunchTheme`; switch `android/app/src/main/res/values/styles.xml` if you target those versions.

## Interface refresh

- Flat white cards on warm ivory, 6–10 px corners, compact spacing and strong text contrast.
- A denser dashboard with actionable counts, illustrated status icons and deadlines closer to the top.
- Responsive phone navigation and a side navigation rail from 900 px; list cards adapt to larger text.
- Coloured vector illustrations and monochrome empty states, bundled locally without network dependencies.
- **Pinned obligations:** use the bookmark on a card or detail page. Pins persist per account and company and appear on Home and the Pinned list. They never expand a user's access.
- **Obligation templates:** prefill GST filings, insurance renewals, licence renewals and contract reviews. Users still choose the date and assignee; applying a template to an edited draft requires confirmation.
- **Next seven days:** a compact deadline strip opens the calendar on the selected date.

## Architecture

```text
lib/
  app/                         Bootstrap, Riverpod providers, guarded routes
  core/
    api/                       Dio, secure token store, refresh interception
    config/                    Environment selection and HTTPS validation
    errors/                    Domain-friendly failures
    security/                  App lock, biometrics, passcode hashing, sign-in throttle
    storage/                   Encrypted file, Hive and in-memory persistence adapters
    theme/                     Warm, flat DueDesk visual tokens
    utils/                     Civil dates, recurrence, filtering, permissions
    widgets/                   Cards, forms, shell, illustrations, loading/error states
  features/
    auth/                      Demo and API authentication repositories
    security/                  Lock screen and passcode setup
    due_items/                 Repository contracts, demo/API adapters, workflows
    dashboard/                 Computed summaries and home presentation
    calendar/                  Month and agenda
    documents/                 Upload, listing, preview, download
    notifications/             Inbox, live banner, reminder engine, service boundary
    companies/                 Company and category management
    users/                     Team and invitation flows
    onboarding/ profile/ settings/
  shared/
    models/                    Immutable domain models and JSON serialization
    widgets/                   Due cards, badges, avatars, company switcher
```

Presentation observes Riverpod providers and invokes repository methods through `WorkspaceController`. Business decisions, permissions, and transitions live outside widgets. Feature repositories share a small workspace snapshot to keep V1 understandable and mutations consistent. Model serialization is explicit, so code generation is not required.

`MockDueItemRepository` implements the DueItem, document, company, user, and notification contracts. Mutations are serialised and persisted as one Hive workspace snapshot. File bytes use a separate Hive box. Completed evidence cannot be replaced or removed; new evidence can still be added. `MemoryLocalStore` supports backend-free tests.

The API adapter uses REST and a local read cache. Cached workspace data is bound to the authenticated user to prevent another account from reading a previous account's snapshot. Mutations require a connection; V1 does not queue remote writes or pretend that an offline mutation succeeded.

## Backend configuration

Configuration uses compile-time `--dart-define`; `.env.example` is a reference, not a runtime dotenv loader.

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://your-development-api.example/api/v1

flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://your-production-api.example/api/v1
```

`APP_ENV` accepts `demo`, `development`, or `production`. Non-demo environments require an API URL. Production requires HTTPS. No secrets belong in Dart defines or source code. Secure storage holds production access/refresh tokens; session-only login keeps them in memory.

Connect the Phoenix backend at these boundaries:

- `lib/core/api/api_client.dart`: base URL, bearer token, single-flight refresh, timeouts, API failure mapping.
- `lib/features/auth/data/auth_repositories.dart`: login, registration, restoration, password reset, logout.
- `lib/features/due_items/domain/repositories.dart`: repository interfaces and pagination request.
- `lib/features/due_items/data/api_repository.dart`: DueItems, transactional completion/renewal, files, workspace, company, team, categories, notifications.
- `lib/features/notifications/domain/notification_service.dart`: device registration, permissions, and push-to-route events. FCM or Phoenix Channels can be implemented behind this interface.

The proposed REST contract is in [docs/API_CONTRACT.md](docs/API_CONTRACT.md). It has not been tested against an external DueDesk server because none was supplied. Server authorization must validate membership and scope every object query; Flutter permission checks are defence in depth.

## Date and history rules

- Due dates represent civil dates in the organisation timezone, not UTC instants. `DueDates.today` uses IANA timezone data; date comparisons use civil UTC arithmetic so daylight-saving changes do not alter day counts.
- The warning window follows the earliest enabled reminder (15 days when reminders are disabled). Overdue and today urgency remains visible even when work is in progress. Closed items never become overdue.
- Monthly recurrence preserves end-of-month schedules, including leap years. Custom recurrence is a positive day interval.
- Completing with renewal creates a new identity, carries scheduling/reference/assignment settings, and leaves documents and completion evidence attached to the old record.
- Archives retain history and are available through the Archived status filter.
- Category deactivation prevents new selection and retains existing references.

## Build and verification

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK output: `build/app/outputs/flutter-apk/app-debug.apk`.

Release builds use `android/key.properties` when supplied. The app does not reuse the debug signing key for release. Set `storeFile` (absolute path), `storePassword`, `keyAlias`, and `keyPassword` in that ignored file before producing a signed release. Keep keystores and credentials outside version control.

Tests cover civil dates/timezones, urgency, recurrence, search/filters, summaries, persistence, permissions, concurrency, document validation, authentication, widgets, and guarded navigation. Widget tests load the bundled font and exercise phone/tablet layouts. See [docs/VERIFICATION.md](docs/VERIFICATION.md) for the final run results.

For iOS on macOS (iPhone and iPad, iOS 15+; Swift Package Manager):

```bash
flutter pub get
flutter build ios --simulator
# Select your Apple development team in ios/Runner.xcworkspace before device/archive builds.
flutter build ipa --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://your-production-api.example/api/v1
```

Photo-library purpose text, app-scoped Keychain entitlements, and `duedesk://due/{id}` scheme declarations are included in the platform projects. Associated domains/universal links require deployment-specific configuration.

## Branding and dependencies

`assets/branding/duedesk_mark.svg` is a replaceable temporary DueDesk mark. Platform icons are generated from it. Replace the SVG, full logo, and launcher icons when official branding is available. Inter is bundled with its OFL licence, so typography does not depend on a network request.

Major dependencies: Riverpod, go_router, Dio, Hive CE, shared_preferences, flutter_secure_storage, local_auth, intl, timezone, uuid, cryptography, file_picker, image_picker, pdfrx, connectivity_plus, flutter_svg, shimmer. `pubspec.lock` records resolved versions.

## Production services

Production rollout requires the deployed API and authorization/transaction contract, reminder and push/email delivery services, operator terms/privacy URLs, and Android release/Apple signing configuration. The demo remains fully usable without these services. Local demo storage is not a shared SaaS database and is not a substitute for production backups.
