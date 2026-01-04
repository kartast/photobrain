# Codemagic CI/CD Plan

## Overview

PhotoBrain uses **Codemagic** for CI/CD to build and deploy Flutter apps to TestFlight (iOS) and Play Store (Android) from a Linux development environment.

**Why Codemagic:**
- Flutter-first CI/CD platform
- No Mac required for iOS builds
- 500 free build minutes/month
- Automatic code signing
- Direct TestFlight/Play Store deployment

---

## Build Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                        Git Push                                 │
│                    (main or release/*)                          │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Codemagic Cloud                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │   iOS Workflow      │    │  Android Workflow   │            │
│  │   (macOS M2)        │    │  (Linux)            │            │
│  │                     │    │                     │            │
│  │  1. flutter pub get │    │  1. flutter pub get │            │
│  │  2. flutter test    │    │  2. flutter test    │            │
│  │  3. flutter build   │    │  3. flutter build   │            │
│  │     ipa --release   │    │     appbundle       │            │
│  │  4. Code sign       │    │  4. Sign APK        │            │
│  │  5. Upload to       │    │  5. Upload to       │            │
│  │     TestFlight      │    │     Play Store      │            │
│  └─────────────────────┘    └─────────────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Artifacts                                  │
├─────────────────────────────────────────────────────────────────┤
│  iOS: TestFlight (internal/external testing)                    │
│  Android: Play Store (internal/beta/production tracks)          │
│  Build artifacts stored for 30 days                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup Steps

### 1. Prerequisites

- [ ] Apple Developer Account ($99/year)
- [ ] Google Play Developer Account ($25 one-time)
- [ ] Codemagic account (free tier)
- [ ] Git repository (GitHub/GitLab/Bitbucket)

### 2. Codemagic Account Setup

1. Sign up at [codemagic.io](https://codemagic.io)
2. Connect Git repository
3. Select Flutter project

### 3. iOS Code Signing Setup

**Option A: Automatic (Recommended)**

Codemagic can manage certificates automatically:

1. Go to **Teams** > **Integrations** > **App Store Connect**
2. Create App Store Connect API key:
   - App Store Connect > Users and Access > Keys
   - Generate API key with "App Manager" role
   - Download `.p8` file
3. Add to Codemagic:
   - Issuer ID
   - Key ID
   - API Key (.p8 file)

**Option B: Manual**

Upload certificates manually:
- Distribution certificate (.p12)
- Provisioning profile (.mobileprovision)

### 4. Android Signing Setup

1. Generate keystore:
   ```bash
   keytool -genkey -v -keystore photobrain-release.keystore \
     -alias photobrain -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Upload to Codemagic:
   - Go to **Environment variables**
   - Add `CM_KEYSTORE` (base64 encoded keystore)
   - Add `CM_KEY_ALIAS`
   - Add `CM_KEY_PASSWORD`
   - Add `CM_KEYSTORE_PASSWORD`

3. Create Google Play service account:
   - Google Play Console > Setup > API access
   - Create service account with "Release manager" role
   - Download JSON key
   - Upload to Codemagic

---

## Codemagic Configuration

### codemagic.yaml

```yaml
# codemagic.yaml
workflows:
  # ============================================
  # iOS TestFlight Workflow
  # ============================================
  ios-release:
    name: iOS Release to TestFlight
    instance_type: mac_mini_m2
    max_build_duration: 60

    environment:
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.yourcompany.photobrain
      vars:
        BUNDLE_ID: "com.yourcompany.photobrain"
        APP_STORE_CONNECT_ISSUER_ID: Encrypted(...)
        APP_STORE_CONNECT_KEY_IDENTIFIER: Encrypted(...)
        APP_STORE_CONNECT_PRIVATE_KEY: Encrypted(...)
      flutter: stable
      xcode: latest
      cocoapods: default

    triggering:
      events:
        - push
        - tag
      branch_patterns:
        - pattern: 'main'
          include: true
        - pattern: 'release/*'
          include: true
      tag_patterns:
        - pattern: 'v*'
          include: true

    scripts:
      # Set up local properties
      - name: Set up local.properties
        script: |
          echo "flutter.sdk=$HOME/programs/flutter" > "$CM_BUILD_DIR/android/local.properties"

      # Get Flutter packages
      - name: Get Flutter packages
        script: |
          flutter pub get

      # Run tests
      - name: Run Flutter tests
        script: |
          flutter test
        ignore_failure: false

      # Install CocoaPods
      - name: Install CocoaPods dependencies
        script: |
          cd ios && pod install

      # Set up code signing
      - name: Set up code signing
        script: |
          keychain initialize
          app-store-connect fetch-signing-files "$BUNDLE_ID" \
            --type IOS_APP_STORE \
            --create
          keychain add-certificates
          xcode-project use-profiles

      # Build iOS
      - name: Build iOS
        script: |
          flutter build ipa --release \
            --build-number=$PROJECT_BUILD_NUMBER \
            --export-options-plist=/Users/builder/export_options.plist

    artifacts:
      - build/ios/ipa/*.ipa
      - /tmp/xcodebuild_logs/*.log
      - flutter_drive.log

    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
        beta_groups:
          - "Internal Testers"

      email:
        recipients:
          - your@email.com
        notify:
          success: true
          failure: true

  # ============================================
  # Android Play Store Workflow
  # ============================================
  android-release:
    name: Android Release to Play Store
    instance_type: linux_x2
    max_build_duration: 30

    environment:
      android_signing:
        - photobrain_keystore
      groups:
        - google_play
      vars:
        PACKAGE_NAME: "com.yourcompany.photobrain"
      flutter: stable
      java: 17

    triggering:
      events:
        - push
        - tag
      branch_patterns:
        - pattern: 'main'
          include: true
        - pattern: 'release/*'
          include: true
      tag_patterns:
        - pattern: 'v*'
          include: true

    scripts:
      - name: Get Flutter packages
        script: |
          flutter pub get

      - name: Run Flutter tests
        script: |
          flutter test
        ignore_failure: false

      - name: Build Android App Bundle
        script: |
          flutter build appbundle --release \
            --build-number=$PROJECT_BUILD_NUMBER

    artifacts:
      - build/app/outputs/**/*.aab
      - build/app/outputs/**/*.apk
      - flutter_drive.log

    publishing:
      google_play:
        credentials: Encrypted(...)
        track: internal  # internal, alpha, beta, production
        submit_as_draft: true

      email:
        recipients:
          - your@email.com
        notify:
          success: true
          failure: true

  # ============================================
  # PR Validation Workflow (No Deploy)
  # ============================================
  pr-check:
    name: PR Validation
    instance_type: linux_x2
    max_build_duration: 20

    environment:
      flutter: stable

    triggering:
      events:
        - pull_request
      branch_patterns:
        - pattern: '*'
          include: true

    scripts:
      - name: Get packages
        script: flutter pub get

      - name: Analyze code
        script: flutter analyze --fatal-infos

      - name: Run tests
        script: flutter test --coverage

      - name: Check formatting
        script: dart format --set-exit-if-changed .

    artifacts:
      - coverage/lcov.info
```

---

## Environment Variables

Store these securely in Codemagic:

### iOS Variables

| Variable | Description | Where to Get |
|----------|-------------|--------------|
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID | App Store Connect > Keys |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | API Key ID | App Store Connect > Keys |
| `APP_STORE_CONNECT_PRIVATE_KEY` | .p8 file contents | Downloaded when creating key |

### Android Variables

| Variable | Description | Where to Get |
|----------|-------------|--------------|
| `CM_KEYSTORE` | Base64 keystore | `base64 photobrain-release.keystore` |
| `CM_KEY_ALIAS` | Key alias | Set during keytool generation |
| `CM_KEY_PASSWORD` | Key password | Set during keytool generation |
| `CM_KEYSTORE_PASSWORD` | Keystore password | Set during keytool generation |
| `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Play Console JSON | Google Cloud Console |

---

## Build Triggers

| Trigger | Workflow | Action |
|---------|----------|--------|
| Push to `main` | ios-release, android-release | Build & deploy to TestFlight/Internal |
| Push to `release/*` | ios-release, android-release | Build & deploy |
| Tag `v*` | ios-release, android-release | Build & deploy (production) |
| Pull Request | pr-check | Test & analyze only |

---

## Cost Estimation

### Free Tier (500 min/month)

| Build Type | Duration | Builds/Month |
|------------|----------|--------------|
| iOS (M2 Mac) | ~15-20 min | ~25-33 builds |
| Android (Linux) | ~5-10 min | ~50-100 builds |
| PR Check (Linux) | ~3-5 min | ~100-166 checks |

**Typical Usage:**
- 2-3 iOS builds/week = 8-12 builds/month = 160-240 min
- 2-3 Android builds/week = 8-12 builds/month = 40-120 min
- 10 PR checks/week = 40 checks/month = 120-200 min
- **Total: ~320-560 min/month** (may need Pay-as-you-go)

### Pay-as-you-go Pricing

| Machine | Price |
|---------|-------|
| Mac mini M2 | $0.095/min |
| Linux | $0.02/min |

**Monthly estimate (active development):**
- iOS: 300 min × $0.095 = $28.50
- Android: 100 min × $0.02 = $2.00
- **Total: ~$30/month**

---

## Workflow Commands

### Manual Build Trigger

```bash
# Using Codemagic CLI
pip install codemagic-cli-tools

# Trigger iOS build
codemagic builds start \
  --workflow-id ios-release \
  --branch main

# Check build status
codemagic builds show <build-id>
```

### Local Testing Before Push

```bash
# Run same checks as CI
flutter pub get
flutter analyze --fatal-infos
flutter test
dart format --set-exit-if-changed .

# Build locally (requires Xcode on Mac)
flutter build ipa --release  # iOS
flutter build appbundle      # Android
```

---

## Troubleshooting

### Common Issues

**1. Code signing failed**
```
Error: No signing certificate found
```
Solution: Regenerate certificates in App Store Connect, re-fetch in Codemagic

**2. Pod install failed**
```
Error: CocoaPods could not find compatible versions
```
Solution: Update Podfile.lock, or delete and regenerate:
```bash
cd ios && rm Podfile.lock && pod install --repo-update
```

**3. Build number conflict**
```
Error: Build already exists in TestFlight
```
Solution: Increment build number or use `$PROJECT_BUILD_NUMBER` (auto-increments)

**4. Timeout**
```
Error: Build exceeded maximum duration
```
Solution: Increase `max_build_duration` or optimize build

---

## Security Best Practices

1. **Never commit secrets** — Use Codemagic encrypted variables
2. **Rotate keys regularly** — Update API keys every 6-12 months
3. **Use App Store Connect API** — More secure than password auth
4. **Enable 2FA** — On Apple ID and Google accounts
5. **Limit permissions** — Service accounts should have minimal access

---

## Integration with Development Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Development Flow                             │
└─────────────────────────────────────────────────────────────────┘

1. Feature Development
   └── Create branch: feature/my-feature
   └── Local development & testing
   └── Push to GitHub

2. Pull Request
   └── Codemagic runs pr-check workflow
   └── Tests, lint, format check
   └── Review & approve

3. Merge to Main
   └── Codemagic triggers ios-release + android-release
   └── Builds deployed to TestFlight (iOS) + Internal (Android)
   └── Team gets email notification

4. Release
   └── Create tag: git tag v1.0.0 && git push --tags
   └── Codemagic builds release version
   └── Submit to App Store / Play Store review
```

---

## Files to Add to Project

```
photobrain/
├── codemagic.yaml              # CI/CD configuration
├── ios/
│   └── ExportOptions.plist     # iOS export settings (optional)
└── android/
    └── key.properties          # Local signing (gitignored)
```

### ios/ExportOptions.plist (if needed)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>app-store</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

---

## Next Steps

1. [ ] Create Apple Developer account
2. [ ] Create Google Play Developer account
3. [ ] Sign up for Codemagic
4. [ ] Generate App Store Connect API key
5. [ ] Generate Android signing keystore
6. [ ] Create `codemagic.yaml` in project root
7. [ ] Configure environment variables in Codemagic
8. [ ] Test with first build

---

## Sources

- [Codemagic Documentation](https://docs.codemagic.io/)
- [Flutter CI/CD Guide](https://docs.flutter.dev/deployment/cd)
- [Codemagic Pricing](https://codemagic.io/pricing/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)

---

*Version: 1.0*
*Created: January 2025*
