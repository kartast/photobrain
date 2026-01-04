# SQLite-Vec Cloud Sync Plan

## Overview

This document outlines the architecture for syncing PhotoBrain's SQLite database (including sqlite-vec vector embeddings) across devices using:
- **iOS**: iCloud via CloudKit / CKSyncEngine
- **Android**: Google Drive API

**Key Challenge**: sqlite-vec stores vectors in virtual tables that require special handling for sync.

---

## What Needs to Sync

| Data Type | Size per Photo | 10K Photos | Sync Priority |
|-----------|---------------|------------|---------------|
| Photo metadata | ~500 bytes | 5 MB | High |
| Vector embeddings | ~3 KB (768 floats) | 30 MB | High |
| User notes | ~200 bytes avg | 2 MB | High |
| Albums | ~100 bytes | 1 MB | Medium |
| App settings | ~1 KB total | 1 KB | Low |
| **Total** | ~3.8 KB/photo | **~38 MB** | - |

**What does NOT sync**: Photos themselves (already in iCloud Photos / Google Photos)

---

## Architecture Options

### Option A: File-Based Sync (Simple)
Upload/download entire SQLite DB file.

```
┌─────────────┐         ┌─────────────────────┐
│  Device A   │         │    Cloud Storage    │
│  SQLite DB  │ ──────> │  photobrain.db      │
└─────────────┘         └─────────────────────┘
                               │
                               ▼
                        ┌─────────────┐
                        │  Device B   │
                        │  SQLite DB  │
                        └─────────────┘
```

**Pros:**
- Simple implementation
- sqlite-vec data syncs naturally (same file)
- No schema mapping needed

**Cons:**
- Entire DB re-uploaded on any change
- No incremental sync
- Conflict resolution = last-write-wins (data loss risk)
- Poor for large databases (100K+ photos)

**Best for**: MVP / small libraries (<5K photos)

---

### Option B: Record-Level Sync (Recommended)
Sync individual records, map to cloud storage format.

```
┌─────────────┐         ┌─────────────────────┐
│  Device A   │         │    CloudKit (iOS)   │
│  SQLite DB  │ ──────> │  CKRecord per photo │
│  Change Log │         │  + embedding blob   │
└─────────────┘         └─────────────────────┘
                               │
                               ▼
                        ┌─────────────┐
                        │  Device B   │
                        │  SQLite DB  │
                        └─────────────┘
```

**Pros:**
- Incremental sync (only changed records)
- Better conflict resolution (field-level)
- Efficient for large libraries
- Works offline, syncs when online

**Cons:**
- More complex implementation
- Need to serialize/deserialize vectors
- Platform-specific sync code (iOS vs Android)

**Best for**: Production app with 10K+ photos

---

### Option C: CRDT-Based Sync (Advanced)
Use cr-sqlite or SQLite-Sync for conflict-free replication.

**Pros:**
- Automatic conflict resolution
- Multi-device concurrent edits
- Strong eventual consistency

**Cons:**
- Requires schema modifications (UUIDs, no auto-increment)
- sqlite-vec compatibility unknown
- Higher complexity
- May need custom backend

**Best for**: Apps requiring real-time collaboration

---

## Recommended Approach: Hybrid

**Phase 1 (MVP)**: Option A - File-based sync
- Quick to implement
- Good for beta testing
- Acceptable for <10K photos

**Phase 2 (Production)**: Option B - Record-level sync
- Migrate to CKSyncEngine (iOS) / Drive API (Android)
- Incremental sync for efficiency
- Better UX for large libraries

---

## iOS Implementation: iCloud Sync

### Option 1: CKSyncEngine (Recommended for iOS 17+)

Apple's official sync engine, introduced in iOS 17. Used by Freeform app.

**Architecture:**
```
┌───────────────────────────────────────────────────┐
│                   PhotoBrain App                  │
├───────────────────────────────────────────────────┤
│  SyncService (Platform Channel from Flutter)      │
│  ├── CKSyncEngine                                 │
│  ├── CKSyncEngineDelegate                         │
│  └── Local SQLite + sqlite-vec                    │
├───────────────────────────────────────────────────┤
│  CloudKit Private Database                        │
│  └── PhotoBrainZone                               │
│      ├── CKRecord: PhotoMetadata                  │
│      ├── CKRecord: Embedding (blob)               │
│      ├── CKRecord: Note                           │
│      └── CKRecord: Album                          │
└───────────────────────────────────────────────────┘
```

**CloudKit Record Schema:**

```swift
// PhotoMetadata Record
CKRecord(recordType: "PhotoMetadata")
├── sourceId: String        // PHAsset.localIdentifier
├── captureDate: Date
├── latitude: Double?
├── longitude: Double?
├── locationName: String?
├── description: String     // LLM-generated
├── objects: [String]       // JSON array
├── tags: [String]          // JSON array
├── mood: String?
├── sceneType: String?
├── textDetected: String?   // OCR text
├── analysisVersion: String
├── updatedAt: Date
└── embedding: CKAsset      // Binary blob (3KB)

// Note Record
CKRecord(recordType: "Note")
├── photoId: CKRecord.Reference
├── content: String
├── createdAt: Date
└── updatedAt: Date

// Album Record
CKRecord(recordType: "Album")
├── name: String
├── photoIds: [String]      // Array of photo sourceIds
├── createdAt: Date
└── updatedAt: Date
```

**Implementation Steps:**

1. **Setup CloudKit Container**
   ```swift
   // In Xcode: Add CloudKit capability
   // Container: iCloud.com.yourcompany.photobrain
   ```

2. **Initialize CKSyncEngine**
   ```swift
   class CloudKitSyncService {
       private var syncEngine: CKSyncEngine!
       private let container = CKContainer(identifier: "iCloud.com.yourcompany.photobrain")

       init() {
           let config = CKSyncEngine.Configuration(
               database: container.privateCloudDatabase,
               stateSerialization: loadSavedState(),
               delegate: self
           )
           syncEngine = CKSyncEngine(config)
       }
   }
   ```

3. **Handle Sync Events**
   ```swift
   extension CloudKitSyncService: CKSyncEngineDelegate {
       func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
           switch event {
           case .stateUpdate(let stateUpdate):
               saveSyncState(stateUpdate.stateSerialization)
           case .accountChange(let event):
               handleAccountChange(event)
           case .fetchedDatabaseChanges(let event):
               handleFetchedChanges(event)
           case .sentDatabaseChanges(let event):
               handleSentChanges(event)
           // ... handle other events
           }
       }

       func nextRecordZoneChangeBatch(
           _ context: CKSyncEngine.SendChangesContext,
           syncEngine: CKSyncEngine
       ) -> CKSyncEngine.RecordZoneChangeBatch? {
           // Return pending changes to upload
           let pendingChanges = getPendingLocalChanges()
           return CKSyncEngine.RecordZoneChangeBatch(
               recordsToSave: pendingChanges.records,
               recordIDsToDelete: pendingChanges.deletions,
               atomicByZone: false
           )
       }
   }
   ```

4. **Vector Embedding Sync**
   ```swift
   // Serialize 768-dim vector to Data
   func serializeEmbedding(_ embedding: [Float]) -> Data {
       return embedding.withUnsafeBytes { Data($0) }
   }

   // Deserialize Data to vector
   func deserializeEmbedding(_ data: Data) -> [Float] {
       return data.withUnsafeBytes {
           Array($0.bindMemory(to: Float.self))
       }
   }

   // Store as CKAsset for large binary data
   func createEmbeddingAsset(_ embedding: [Float]) -> CKAsset {
       let data = serializeEmbedding(embedding)
       let tempURL = FileManager.default.temporaryDirectory
           .appendingPathComponent(UUID().uuidString)
       try? data.write(to: tempURL)
       return CKAsset(fileURL: tempURL)
   }
   ```

5. **Flutter Platform Channel**
   ```dart
   // lib/services/sync_service.dart
   class iCloudSyncService {
     static const platform = MethodChannel('com.photobrain/sync');

     Future<void> triggerSync() async {
       await platform.invokeMethod('triggerSync');
     }

     Future<SyncStatus> getSyncStatus() async {
       final result = await platform.invokeMethod('getSyncStatus');
       return SyncStatus.fromMap(result);
     }

     Stream<SyncEvent> get syncEvents {
       return const EventChannel('com.photobrain/sync_events')
           .receiveBroadcastStream()
           .map((event) => SyncEvent.fromMap(event));
     }
   }
   ```

**Conflict Resolution Strategy:**

```swift
// For PhotoMetadata: Last-write-wins with field-level merge
func resolveConflict(local: CKRecord, server: CKRecord) -> CKRecord {
    let resolved = server  // Start with server version

    // Preserve local user-modified fields if newer
    if local.modificationDate > server.modificationDate {
        // User notes are more important to preserve
        resolved["customTags"] = local["customTags"]
    }

    // LLM-generated fields: prefer server (re-analysis)
    // Server version wins for: description, objects, tags, embedding

    return resolved
}
```

---

### Option 2: SQLiteData Library (Alternative)

Point-Free's [SQLiteData](https://github.com/pointfreeco/sqlite-data) library provides SQLite + CloudKit sync.

**Pros:**
- Simplified API
- Built-in CloudKit sync
- Supports GRDB

**Cons:**
- Third-party dependency
- Less control over sync behavior
- May not work well with sqlite-vec

---

### Option 3: iCloud Documents (File-Based Fallback)

Simple file-based sync using `NSFileCoordinator`.

```swift
// Store DB in iCloud Documents container
let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
    .appendingPathComponent("Documents")
    .appendingPathComponent("photobrain.db")
```

**Best for**: MVP only. Not recommended for production due to conflict issues.

---

## Android Implementation: Google Drive Sync

### Architecture

```
┌───────────────────────────────────────────────────┐
│                   PhotoBrain App                  │
├───────────────────────────────────────────────────┤
│  SyncService (Platform Channel from Flutter)      │
│  ├── Google Drive API v3                          │
│  ├── Google Sign-In                               │
│  └── Local SQLite + sqlite-vec                    │
├───────────────────────────────────────────────────┤
│  Google Drive (App Data Folder)                   │
│  └── /appDataFolder/                              │
│      ├── metadata.json  (change log)              │
│      ├── photos/        (record chunks)           │
│      │   ├── chunk_001.json                       │
│      │   ├── chunk_002.json                       │
│      │   └── ...                                  │
│      └── embeddings/    (binary blobs)            │
│          ├── embed_001.bin                        │
│          └── ...                                  │
└───────────────────────────────────────────────────┘
```

### Implementation Steps

1. **Setup Google Sign-In**
   ```kotlin
   // Add dependencies
   implementation("com.google.android.gms:play-services-auth:21.0.0")
   implementation("com.google.api-client:google-api-client-android:2.2.0")
   implementation("com.google.apis:google-api-services-drive:v3-rev20231128-2.0.0")
   ```

2. **Request Drive Scope**
   ```kotlin
   val signInOptions = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
       .requestEmail()
       .requestScopes(Scope(DriveScopes.DRIVE_APPDATA))  // App-specific folder only
       .build()
   ```

3. **DriveSync Service**
   ```kotlin
   class GoogleDriveSyncService(private val context: Context) {
       private var driveService: Drive? = null

       suspend fun initializeDrive(account: GoogleSignInAccount) {
           val credential = GoogleAccountCredential.usingOAuth2(
               context, listOf(DriveScopes.DRIVE_APPDATA)
           )
           credential.selectedAccount = account.account

           driveService = Drive.Builder(
               NetHttpTransport(),
               GsonFactory.getDefaultInstance(),
               credential
           ).setApplicationName("PhotoBrain").build()
       }

       // Upload changes as JSON chunks
       suspend fun uploadChanges(changes: List<PhotoChange>) {
           val json = Gson().toJson(changes)
           val metadata = File()
               .setName("changes_${System.currentTimeMillis()}.json")
               .setParents(listOf("appDataFolder"))

           val content = ByteArrayContent.fromString("application/json", json)
           driveService?.files()?.create(metadata, content)?.execute()
       }

       // Upload embedding as binary
       suspend fun uploadEmbedding(photoId: String, embedding: FloatArray) {
           val buffer = ByteBuffer.allocate(embedding.size * 4)
           embedding.forEach { buffer.putFloat(it) }

           val metadata = File()
               .setName("embed_$photoId.bin")
               .setParents(listOf("appDataFolder"))

           val content = ByteArrayContent("application/octet-stream", buffer.array())
           driveService?.files()?.create(metadata, content)?.execute()
       }
   }
   ```

4. **Change Log Strategy**
   ```kotlin
   data class ChangeLog(
       val version: Long,
       val deviceId: String,
       val timestamp: Long,
       val changes: List<Change>
   )

   data class Change(
       val type: ChangeType,  // INSERT, UPDATE, DELETE
       val table: String,     // photos, notes, albums
       val recordId: String,
       val data: Map<String, Any?>?,
       val timestamp: Long
   )

   // On sync: merge change logs by timestamp
   fun mergeChangeLogs(local: ChangeLog, remote: ChangeLog): List<Change> {
       val allChanges = (local.changes + remote.changes)
           .sortedBy { it.timestamp }
           .distinctBy { "${it.table}_${it.recordId}" }  // Last-write-wins
       return allChanges
   }
   ```

5. **Flutter Platform Channel**
   ```dart
   class GoogleDriveSyncService {
     static const platform = MethodChannel('com.photobrain/sync');

     Future<bool> signIn() async {
       return await platform.invokeMethod('googleSignIn');
     }

     Future<void> sync() async {
       await platform.invokeMethod('syncWithDrive');
     }

     Future<void> signOut() async {
       await platform.invokeMethod('googleSignOut');
     }
   }
   ```

### Conflict Resolution (Android)

```kotlin
// Last-write-wins with tombstones
data class SyncRecord(
    val id: String,
    val data: Map<String, Any?>,
    val updatedAt: Long,
    val deleted: Boolean = false,
    val deviceId: String
)

fun resolveConflicts(local: List<SyncRecord>, remote: List<SyncRecord>): List<SyncRecord> {
    val merged = mutableMapOf<String, SyncRecord>()

    // Add all records, later timestamps win
    (local + remote).forEach { record ->
        val existing = merged[record.id]
        if (existing == null || record.updatedAt > existing.updatedAt) {
            merged[record.id] = record
        }
    }

    return merged.values.toList()
}
```

---

## sqlite-vec Specific Considerations

### Challenge
sqlite-vec uses virtual tables that may not transfer directly.

```sql
-- sqlite-vec creates virtual tables like:
CREATE VIRTUAL TABLE vec_embeddings USING vec0(
    photo_id TEXT PRIMARY KEY,
    embedding FLOAT[768]
);
```

### Solution: Separate Vector Storage

Store embeddings in a regular table for sync, rebuild vec index on load:

```sql
-- Regular table for sync
CREATE TABLE embeddings_sync (
    photo_id TEXT PRIMARY KEY,
    embedding BLOB NOT NULL,  -- 768 floats as binary
    updated_at INTEGER NOT NULL
);

-- Virtual table for search (rebuilt from embeddings_sync)
CREATE VIRTUAL TABLE vec_embeddings USING vec0(
    photo_id TEXT PRIMARY KEY,
    embedding FLOAT[768]
);
```

```dart
// On app start or after sync:
Future<void> rebuildVectorIndex() async {
  await db.execute('DELETE FROM vec_embeddings');
  await db.execute('''
    INSERT INTO vec_embeddings (photo_id, embedding)
    SELECT photo_id, embedding FROM embeddings_sync
  ''');
}
```

---

## Unified Flutter Interface

```dart
// lib/services/sync_service.dart

abstract class SyncService {
  Future<void> initialize();
  Future<void> sync();
  Future<SyncStatus> getStatus();
  Stream<SyncProgress> get progress;
  Future<void> signOut();
}

class SyncServiceFactory {
  static SyncService create() {
    if (Platform.isIOS) {
      return iCloudSyncService();
    } else if (Platform.isAndroid) {
      return GoogleDriveSyncService();
    }
    throw UnsupportedError('Platform not supported');
  }
}

// Usage
final syncService = SyncServiceFactory.create();
await syncService.initialize();
await syncService.sync();
```

---

## Sync Status UI

```dart
// lib/widgets/sync_status_indicator.dart

class SyncStatusIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStateProvider);

    return switch (syncState) {
      SyncState.idle => Icon(Icons.cloud_done, color: Colors.green),
      SyncState.syncing => CircularProgressIndicator(),
      SyncState.error => Icon(Icons.cloud_off, color: Colors.red),
      SyncState.offline => Icon(Icons.cloud_queue, color: Colors.grey),
    };
  }
}
```

---

## Implementation Phases

### Phase 1: MVP File Sync (Week 1-2)

- [ ] iOS: iCloud Documents file sync
- [ ] Android: Google Drive file upload/download
- [ ] Flutter: Unified sync interface
- [ ] UI: Basic sync status indicator
- [ ] Manual sync trigger button

**Limitations**: Full DB upload on every change, basic LWW conflicts

### Phase 2: Record-Level Sync (Week 3-4)

- [ ] iOS: Migrate to CKSyncEngine
- [ ] iOS: CloudKit schema setup
- [ ] iOS: Record mapping (SQLite ↔ CKRecord)
- [ ] Android: JSON change log system
- [ ] Android: Incremental sync
- [ ] Both: Embedding blob handling
- [ ] Both: Conflict resolution

### Phase 3: Polish (Week 5)

- [ ] Background sync (BGProcessingTask / WorkManager)
- [ ] Sync progress UI with details
- [ ] Error recovery and retry logic
- [ ] Bandwidth optimization (Wi-Fi only option)
- [ ] Initial sync optimization (chunked)

---

## Testing Strategy

### Unit Tests
- Serialization/deserialization of vectors
- Conflict resolution logic
- Change detection

### Integration Tests
- iCloud sync with multiple simulators
- Google Drive API mock tests
- Cross-device sync scenarios

### Manual Testing
- Two iOS devices with same iCloud account
- Two Android devices with same Google account
- Large library sync (10K+ photos)
- Offline → Online sync
- Conflict scenarios

---

## Cost Considerations

| Platform | Storage Limit | Cost | Notes |
|----------|--------------|------|-------|
| iCloud | 5 GB free | User's account | No cost to developer |
| Google Drive | 15 GB free | User's account | No cost to developer |

**Typical Usage (10K photos):**
- Metadata + embeddings: ~38 MB
- Well under free tier limits

---

## Security Considerations

1. **Data at Rest**: Both iCloud and Google Drive encrypt data
2. **Data in Transit**: TLS/SSL for all transfers
3. **Access Control**: User's own cloud account (private)
4. **No Backend Storage**: PhotoBrain server never stores user data

---

## Sources

- [CKSyncEngine - Apple Documentation](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [WWDC23: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [Apple CloudKit Sync Engine Sample](https://github.com/apple/sample-cloudkit-sync-engine)
- [SQLiteData by Point-Free](https://github.com/pointfreeco/sqlite-data)
- [Superwall: Syncing with CloudKit using CKSyncEngine](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/)
- [Google Drive API v3](https://developers.google.com/drive/api/v3/about-sdk)
- [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec)
- [cr-sqlite: CRDT for SQLite](https://github.com/vlcn-io/cr-sqlite)
- [SQLite-Sync by SQLite AI](https://github.com/sqliteai/sqlite-sync)
- [Conflict Resolution: LWW vs CRDTs](https://dzone.com/articles/conflict-resolution-using-last-write-wins-vs-crdts)

---

*Version: 1.0*
*Created: January 2025*
