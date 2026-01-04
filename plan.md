# PhotoBrain MVP Plan

## Overview

MVP delivery based on PRD decisions:

- **Framework**: Flutter
- **LLM**: Gemini 2.5 Flash
- **Database**: SQLite (local)
- **Storage**: Client-first (data on device)
- **Sync**: iCloud / Google Drive
- **Backend**: Proxy server for LLM API
- **Monetization**: Subscription
- **CI/CD**: Codemagic (build iOS/Android from Linux)

---

## MVP Scope

**In Scope**
- Photo library access (iOS + Android)
- Metadata extraction (EXIF, GPS)
- Cloud LLM analysis
- Semantic search
- Photo browsing UI
- User notes
- Albums

**Out of Scope**
- On-device ML
- Camera features
- Voice notes
- Analytics dashboard
- Export/sharing

---

## Phase 1: Foundation

Week 1-2

### 1.1 Environment Setup

- [ ] Install Flutter SDK
- [ ] Configure Android Studio + Xcode
- [ ] Set up test devices
- [ ] Create Flutter project
- [ ] Configure Git

### 1.2 Project Structure

- [ ] Create folders: config, models, services, repositories, providers, screens, widgets

### 1.3 Dependencies

- [ ] photo_manager
- [ ] sqflite
- [ ] sqlite_vec (FFI)
- [ ] path_provider
- [ ] dio
- [ ] riverpod
- [ ] cached_network_image
- [ ] flutter_secure_storage
- [ ] permission_handler

### 1.4 Platform Config

**iOS Info.plist:**
- [ ] NSPhotoLibraryUsageDescription
- [ ] NSPhotoLibraryAddUsageDescription

**Android Manifest:**
- [ ] READ_MEDIA_IMAGES
- [ ] READ_EXTERNAL_STORAGE
- [ ] Internet permission

---

## Phase 2: Data Layer

Week 2-3

### 2.1 Database Schema

- [ ] SQLite helper class
- [ ] photos table
- [ ] metadata_native table
- [ ] metadata_llm table
- [ ] notes table
- [ ] albums table
- [ ] album_photos table
- [ ] Migrations system
- [ ] Search indexes

### 2.2 Data Models

- [ ] Photo model
- [ ] NativeMetadata model
- [ ] LLMMetadata model
- [ ] Note model
- [ ] Album model
- [ ] Connection model

### 2.3 Repositories

- [ ] PhotoRepository
- [ ] MetadataRepository
- [ ] NoteRepository
- [ ] AlbumRepository
- [ ] Query builders

---

## Phase 3: Photo Library

Week 3-4

### 3.1 Photo Access

- [ ] Init photo_manager
- [ ] Permission UI
- [ ] Handle denied permissions
- [ ] Limited access (iOS 14+)

### 3.2 Import Pipeline

- [ ] Fetch all photos
- [ ] Pagination (100/batch)
- [ ] Extract metadata
- [ ] Content hash
- [ ] Save to database
- [ ] Track sync state

### 3.3 Incremental Sync

- [ ] Detect new photos
- [ ] Detect deleted
- [ ] Detect modified
- [ ] Background scheduler
- [ ] Status indicator

### 3.4 Image Loading

- [ ] Thumbnails
- [ ] Full resolution
- [ ] Caching
- [ ] Placeholders

---

## Phase 4: Backend + LLM Integration

Week 4-6

### 4.1 Proxy Server Setup

- [ ] Cloudflare Workers or Vercel
- [ ] Auth endpoint (JWT)
- [ ] Gemini proxy endpoint
- [ ] Rate limiting per user
- [ ] Usage tracking

### 4.2 Subscription (Stripe)

- [ ] Stripe account setup
- [ ] Subscription products (Free/Pro/Unlimited)
- [ ] Webhook for subscription events
- [ ] In-app purchase (iOS/Android)
- [ ] Subscription status check

### 4.3 App ↔ Server Integration

- [ ] User auth flow
- [ ] Secure API calls
- [ ] Handle subscription tiers
- [ ] Offline graceful degradation

### 4.4 Photo Analysis

- [ ] Resize images (1024px max)
- [ ] Send to proxy server
- [ ] Request embedding in same call
- [ ] Parse response + embedding
- [ ] Error handling
- [ ] Retry with backoff

### 4.5 Batch Processing

- [ ] Queue system
- [ ] Background processing
- [ ] Respect rate limits
- [ ] Progress UI
- [ ] Pause/resume
- [ ] Usage tracking UI

---

## Phase 5: Core UI

Week 5-7

### 5.1 Home (Photo Grid)

- [ ] Grid layout
- [ ] Infinite scroll
- [ ] Pull-to-refresh
- [ ] Sort options
- [ ] Filters
- [ ] Selection mode

### 5.2 Photo Detail

- [ ] Full-screen view
- [ ] Swipe navigation
- [ ] Pinch to zoom
- [ ] Metadata panel
- [ ] Notes section
- [ ] Add to album
- [ ] Re-analyze button

### 5.3 Search

- [ ] Search bar
- [ ] History/suggestions
- [ ] Results grid
- [ ] Filter chips
- [ ] Empty state

### 5.4 Albums

- [ ] Album list
- [ ] Create album
- [ ] Album detail
- [ ] Edit album
- [ ] Add/remove photos

### 5.5 Settings

- [ ] Cloud toggle
- [ ] Storage usage
- [ ] Clear cache
- [ ] About/version
- [ ] Privacy policy

---

## Phase 6: Search

Week 7-8

### 6.1 Text Search

- [ ] Search descriptions
- [ ] Search objects
- [ ] Search tags
- [ ] Search notes
- [ ] Search locations
- [ ] FTS5 implementation
- [ ] Ranking

### 6.2 Vector Search

- [ ] Get embeddings from Gemini API
- [ ] Store 768-dim vectors locally
- [ ] sqlite-vec integration
- [ ] "Find similar" feature
- [ ] Text query embedding
- [ ] Duplicate detection

### 6.3 Filters

- [ ] Date range
- [ ] Has location
- [ ] Has people
- [ ] Scene type
- [ ] Mood
- [ ] Combined filters

### 6.4 UX

- [ ] Debounced input
- [ ] Loading states
- [ ] Result count
- [ ] Clear action

---

## Phase 7: User Notes

Week 8

### 7.1 Notes Feature

- [ ] Add note button
- [ ] Note editor
- [ ] Save/update
- [ ] Delete
- [ ] Multiple notes
- [ ] Timestamps

### 7.2 Notes Search

- [ ] Include in FTS
- [ ] Highlight matches
- [ ] Filter option

---

## Phase 8: Cloud Sync

Week 8-9

### 8.1 iOS - iCloud Sync

- [ ] CloudKit setup
- [ ] Sync SQLite to iCloud
- [ ] Conflict resolution
- [ ] Sync status UI

### 8.2 Android - Google Drive

- [ ] Google Drive API setup
- [ ] OAuth flow
- [ ] Sync SQLite to Drive
- [ ] Conflict resolution
- [ ] Sync status UI

---

## Phase 9: Polish

Week 9-11

### 9.1 Performance

- [ ] Profile memory
- [ ] Optimize images
- [ ] Optimize queries
- [ ] Reduce startup time
- [ ] Background efficiency

### 9.2 Error Handling

- [ ] Network errors
- [ ] API errors
- [ ] Database recovery
- [ ] Crash reporting

### 9.3 Testing

- [ ] Unit tests (services)
- [ ] Unit tests (repos)
- [ ] Widget tests
- [ ] Integration tests
- [ ] Manual testing

### 9.4 UI Polish

- [ ] Loading skeletons
- [ ] Empty states
- [ ] Error states
- [ ] Animations
- [ ] Haptic feedback
- [ ] Dark mode

---

## Phase 10: Release

Week 11-13

### 10.1 Assets

- [ ] App icon
- [ ] Screenshots
- [ ] Description
- [ ] Privacy policy
- [ ] Terms of service

### 10.2 CI/CD Setup (Codemagic)

**Why Codemagic:** Build iOS from Linux, 500 free min/month, Flutter-first.

**Prerequisites:**
- [ ] Apple Developer Account ($99/year)
- [ ] Google Play Developer Account ($25 one-time)
- [ ] Codemagic account (free)

**iOS Setup:**
- [ ] App Store Connect API key (.p8)
- [ ] Bundle identifier registration
- [ ] Connect Codemagic to App Store Connect

**Android Setup:**
- [ ] Generate release keystore
- [ ] Google Play service account JSON
- [ ] Upload signing credentials to Codemagic

**Workflows:**
- [ ] `ios-release`: Push to main → TestFlight
- [ ] `android-release`: Push to main → Play Store Internal
- [ ] `pr-check`: PR → Run tests only

**codemagic.yaml:**
```yaml
workflows:
  ios-release:
    name: iOS Release
    instance_type: mac_mini_m2
    environment:
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.yourcompany.photobrain
      flutter: stable
    scripts:
      - flutter pub get
      - flutter test
      - cd ios && pod install
      - flutter build ipa --release
    publishing:
      app_store_connect:
        submit_to_testflight: true

  android-release:
    name: Android Release
    instance_type: linux_x2
    environment:
      flutter: stable
    scripts:
      - flutter pub get
      - flutter test
      - flutter build appbundle --release
    publishing:
      google_play:
        track: internal
```

**Cost:** Free tier (500 min) ≈ 25 iOS builds/month. Pay-as-you-go ~$30/month.

### 10.3 Store Setup

**iOS:**
- [ ] App Store Connect app listing
- [ ] TestFlight beta groups
- [ ] Review compliance checklist
- [ ] Permission rationale strings

**Android:**
- [ ] Play Console app listing
- [ ] Internal testing track
- [ ] Content rating questionnaire
- [ ] Data safety form

### 10.4 Launch

- [ ] Beta feedback collection
- [ ] Bug fixes from beta
- [ ] Submit for review
- [ ] Monitor crash reports
- [ ] User feedback loop

---

## Key Files

**Flutter App:**

| File | Purpose |
|------|---------|
| main.dart | Entry point |
| app.dart | App config |
| photo.dart | Photo model |
| note.dart | Note model |
| photo_service.dart | Library access |
| database_service.dart | SQLite |
| vector_service.dart | Embeddings |
| api_service.dart | Proxy server calls |
| auth_service.dart | User auth |
| sync_service.dart | iCloud/Drive |
| search_service.dart | Search |
| home_screen.dart | Photo grid |
| photo_detail_screen.dart | Viewer |
| search_screen.dart | Search UI |
| subscription_screen.dart | Manage sub |
| codemagic.yaml | CI/CD config |

**Proxy Server:**

| File | Purpose |
|------|---------|
| index.ts | Main entry |
| auth.ts | JWT validation |
| gemini.ts | LLM proxy |
| stripe.ts | Webhooks |
| rate-limit.ts | Usage limits |

---

## Success Criteria

1. Photo permissions work
2. Photos display in grid
3. Full-screen viewing
4. 100+ photos analyzed
5. Text search works
6. Notes addable
7. Notes searchable
8. Albums work
9. Subscription flow works
10. iOS 15+ / Android 10+
11. No critical crashes

---

## Timeline

| Phase | Duration |
|-------|----------|
| Foundation | 2 wks |
| Data Layer | 1 wk |
| Photo Library | 1 wk |
| Backend + LLM | 2 wks |
| Core UI | 2 wks |
| Search | 1 wk |
| Notes | 0.5 wk |
| Cloud Sync | 1.5 wks |
| Polish | 2 wks |
| Release | 2 wks |

**Total: ~15 weeks**

---

*v1.0 - January 2025*
