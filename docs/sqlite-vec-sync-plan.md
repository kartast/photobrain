# SQLite-Vec Cloud Sync Plan

## Overview

This document outlines the architecture for syncing PhotoBrain's SQLite database (including sqlite-vec vector embeddings) across devices using **record-level sync**:

- **iOS**: CloudKit with CKSyncEngine (iOS 17+)
- **Android**: Google Drive API with JSON change logs
- **Framework**: Flutter with native platform channels

**Approach**: Each SQLite row maps to a CloudKit record (CKRecord). Changes sync incrementally, not as full database files.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Flutter App (Dart)                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────────────────┐ │
│  │ UI Layer      │  │ State Mgmt    │  │ Services                │ │
│  │ (Widgets)     │  │ (Riverpod)    │  │ • PhotoService          │ │
│  │               │  │               │  │ • SearchService         │ │
│  └───────────────┘  └───────────────┘  │ • LLMService            │ │
│                                        └─────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│                         Data Layer (Dart)                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  DatabaseService (sqflite + sqlite-vec FFI)                  │   │
│  │  ├── photos table           ← Syncs to CKRecord              │   │
│  │  ├── metadata_llm table     ← Syncs to CKRecord              │   │
│  │  ├── notes table            ← Syncs to CKRecord              │   │
│  │  ├── albums table           ← Syncs to CKRecord              │   │
│  │  ├── embeddings_sync table  ← Syncs as CKAsset (blob)        │   │
│  │  └── vec_embeddings (virtual) ← Rebuilt locally from sync    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  SyncService (Dart interface)                                │   │
│  │  ├── queueChange(table, recordId, data)                      │   │
│  │  ├── sync()                                                  │   │
│  │  └── onRemoteChange(callback)                                │   │
│  └─────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│                    Platform Channel Bridge                          │
│                  MethodChannel + EventChannel                       │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
          ┌─────────────────┴─────────────────┐
          ▼                                   ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│    iOS Native (Swift)   │     │  Android Native (Kotlin) │
│                         │     │                         │
│  CKSyncEngine           │     │  Google Drive API v3    │
│  ├── CKRecord mapping   │     │  ├── JSON record files  │
│  ├── CKAsset (vectors)  │     │  ├── Binary embeddings  │
│  └── Conflict resolve   │     │  └── Change log merge   │
│                         │     │                         │
│  CloudKit Private DB    │     │  Drive appDataFolder    │
│  └── PhotoBrainZone     │     │  └── /photobrain/       │
└─────────────────────────┘     └─────────────────────────┘
```

---

## Data Model & Sync Mapping

### SQLite Schema (Flutter/Dart)

```sql
-- Core photo record
CREATE TABLE photos (
    id TEXT PRIMARY KEY,              -- UUID
    source_id TEXT NOT NULL,          -- PHAsset.localIdentifier / MediaStore._ID
    source TEXT NOT NULL,             -- 'ios' or 'android'
    capture_date INTEGER,
    latitude REAL,
    longitude REAL,
    location_name TEXT,
    file_hash TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_status TEXT DEFAULT 'pending'  -- pending, synced, conflict
);

-- LLM-generated metadata
CREATE TABLE metadata_llm (
    photo_id TEXT PRIMARY KEY REFERENCES photos(id),
    description TEXT,
    objects TEXT,                     -- JSON array
    tags TEXT,                        -- JSON array
    mood TEXT,
    scene_type TEXT,
    text_detected TEXT,
    analysis_version TEXT,
    updated_at INTEGER NOT NULL
);

-- User notes
CREATE TABLE notes (
    id TEXT PRIMARY KEY,
    photo_id TEXT NOT NULL REFERENCES photos(id),
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Albums
CREATE TABLE albums (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    photo_ids TEXT,                   -- JSON array of photo IDs
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Embeddings (regular table for sync)
CREATE TABLE embeddings_sync (
    photo_id TEXT PRIMARY KEY REFERENCES photos(id),
    embedding BLOB NOT NULL,          -- 768 floats × 4 bytes = 3072 bytes
    updated_at INTEGER NOT NULL
);

-- Vector search index (virtual table, rebuilt locally)
CREATE VIRTUAL TABLE vec_embeddings USING vec0(
    photo_id TEXT PRIMARY KEY,
    embedding FLOAT[768]
);

-- Local change tracking (not synced)
CREATE TABLE sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    operation TEXT NOT NULL,          -- INSERT, UPDATE, DELETE
    data TEXT,                        -- JSON payload
    created_at INTEGER NOT NULL,
    UNIQUE(table_name, record_id)
);
```

### CloudKit Record Mapping (iOS)

| SQLite Table | CKRecord Type | Key Fields | Notes |
|--------------|---------------|------------|-------|
| `photos` | `Photo` | id, source_id, capture_date, location, etc. | Core record |
| `metadata_llm` | `PhotoMetadata` | photo_id (reference), description, objects, tags | Linked to Photo |
| `notes` | `Note` | id, photo_id (reference), content | One-to-many |
| `albums` | `Album` | id, name, photo_ids | Contains array |
| `embeddings_sync` | `Embedding` | photo_id (reference), data (CKAsset) | Binary blob |

### CloudKit Schema Definition

```swift
// Record Types in CloudKit Dashboard or code

// Photo Record
struct PhotoRecord {
    static let recordType = "Photo"

    // Fields
    static let id = "id"                    // String
    static let sourceId = "sourceId"        // String
    static let source = "source"            // String
    static let captureDate = "captureDate"  // Date
    static let latitude = "latitude"        // Double
    static let longitude = "longitude"      // Double
    static let locationName = "locationName"// String
    static let fileHash = "fileHash"        // String
    static let createdAt = "createdAt"      // Date
    static let updatedAt = "updatedAt"      // Date
}

// PhotoMetadata Record
struct PhotoMetadataRecord {
    static let recordType = "PhotoMetadata"

    static let photoRef = "photoRef"        // Reference to Photo
    static let description = "description"  // String
    static let objects = "objects"          // List<String>
    static let tags = "tags"                // List<String>
    static let mood = "mood"                // String
    static let sceneType = "sceneType"      // String
    static let textDetected = "textDetected"// String
    static let analysisVersion = "analysisVersion" // String
    static let updatedAt = "updatedAt"      // Date
}

// Embedding Record
struct EmbeddingRecord {
    static let recordType = "Embedding"

    static let photoRef = "photoRef"        // Reference to Photo
    static let data = "data"                // Asset (binary blob)
    static let updatedAt = "updatedAt"      // Date
}

// Note Record
struct NoteRecord {
    static let recordType = "Note"

    static let id = "id"                    // String
    static let photoRef = "photoRef"        // Reference to Photo
    static let content = "content"          // String
    static let createdAt = "createdAt"      // Date
    static let updatedAt = "updatedAt"      // Date
}

// Album Record
struct AlbumRecord {
    static let recordType = "Album"

    static let id = "id"                    // String
    static let name = "name"                // String
    static let photoIds = "photoIds"        // List<String>
    static let createdAt = "createdAt"      // Date
    static let updatedAt = "updatedAt"      // Date
}
```

---

## iOS Implementation: CKSyncEngine

### 1. Project Setup

**Xcode Capabilities:**
- iCloud → CloudKit
- Background Modes → Remote notifications
- Push Notifications

**Container:** `iCloud.com.yourcompany.photobrain`

### 2. Core Sync Service (Swift)

```swift
// ios/Runner/CloudKitSyncService.swift

import CloudKit
import Flutter

class CloudKitSyncService: NSObject {

    // MARK: - Properties

    private var syncEngine: CKSyncEngine!
    private let container = CKContainer(identifier: "iCloud.com.yourcompany.photobrain")
    private let zoneID = CKRecordZone.ID(zoneName: "PhotoBrainZone", ownerName: CKCurrentUserDefaultName)

    private var pendingChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    private var eventSink: FlutterEventSink?

    // MARK: - Initialization

    func initialize() {
        // Load saved state or create new
        let savedState = loadSyncState()

        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: savedState,
            delegate: self
        )

        syncEngine = CKSyncEngine(config)

        // Create zone if needed
        Task {
            await createZoneIfNeeded()
        }
    }

    // MARK: - Zone Management

    private func createZoneIfNeeded() async {
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            try await container.privateCloudDatabase.save(zone)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists, that's fine
        } catch {
            print("Failed to create zone: \(error)")
        }
    }

    // MARK: - State Persistence

    private func loadSyncState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: "cloudkit_sync_state") else {
            return nil
        }
        return try? CKSyncEngine.State.Serialization(from: data)
    }

    private func saveSyncState(_ state: CKSyncEngine.State.Serialization) {
        if let data = try? state.data() {
            UserDefaults.standard.set(data, forKey: "cloudkit_sync_state")
        }
    }

    // MARK: - Public API (called from Flutter)

    func queueRecordChange(recordType: String, recordId: String, data: [String: Any]) {
        let recordID = CKRecord.ID(recordName: recordId, zoneID: zoneID)
        let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID)
        pendingChanges.append(change)

        // Store data for when engine requests it
        savePendingData(recordType: recordType, recordId: recordId, data: data)

        // Notify engine of pending changes
        syncEngine.state.add(pendingRecordZoneChanges: [change])
    }

    func queueRecordDeletion(recordType: String, recordId: String) {
        let recordID = CKRecord.ID(recordName: recordId, zoneID: zoneID)
        let change = CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID)

        syncEngine.state.add(pendingRecordZoneChanges: [change])
    }

    func triggerSync() {
        Task {
            try? await syncEngine.fetchChanges()
            try? await syncEngine.sendChanges()
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncService: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            saveSyncState(stateUpdate.stateSerialization)

        case .accountChange(let event):
            handleAccountChange(event)

        case .fetchedDatabaseChanges(let event):
            // Process fetched changes
            for modification in event.modifications {
                handleFetchedRecord(modification.record)
            }
            for deletion in event.deletions {
                handleDeletedRecord(deletion.recordID)
            }

        case .fetchedRecordZoneChanges(let event):
            for modification in event.modifications {
                handleFetchedRecord(modification.record)
            }
            for deletion in event.deletions {
                handleDeletedRecord(deletion.recordID)
            }

        case .sentRecordZoneChanges(let event):
            // Handle successful uploads
            for saved in event.savedRecords {
                markRecordSynced(saved.recordID)
            }
            // Handle failures
            for (recordID, error) in event.failedRecordSaves {
                handleSaveFailure(recordID: recordID, error: error)
            }

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges, .didFetchChanges:
            // Progress events - notify Flutter
            sendProgressEvent(event)

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {

        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
            .filter { $0.zoneID == zoneID }

        guard !pendingChanges.isEmpty else { return nil }

        // Build records from pending data
        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in pendingChanges {
            switch change {
            case .saveRecord(let recordID):
                if let record = buildRecord(for: recordID) {
                    recordsToSave.append(record)
                }
            case .deleteRecord(let recordID):
                recordIDsToDelete.append(recordID)
            @unknown default:
                break
            }
        }

        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete,
            atomicByZone: false
        )
    }

    // MARK: - Record Building

    private func buildRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let pendingData = loadPendingData(recordId: recordID.recordName) else {
            return nil
        }

        let recordType = pendingData["_recordType"] as! String
        let record = CKRecord(recordType: recordType, recordID: recordID)

        // Map data fields to CKRecord
        for (key, value) in pendingData where !key.hasPrefix("_") {
            if key == "embedding", let embeddingData = value as? FlutterStandardTypedData {
                // Handle embedding as CKAsset
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".bin")
                try? embeddingData.data.write(to: tempURL)
                record[key] = CKAsset(fileURL: tempURL)
            } else if let date = value as? Double {
                // Handle timestamps
                record[key] = Date(timeIntervalSince1970: date / 1000) as CKRecordValue
            } else if let array = value as? [String] {
                record[key] = array as CKRecordValue
            } else if let string = value as? String {
                record[key] = string as CKRecordValue
            } else if let number = value as? NSNumber {
                record[key] = number as CKRecordValue
            }
        }

        return record
    }

    // MARK: - Handling Fetched Records

    private func handleFetchedRecord(_ record: CKRecord) {
        var data: [String: Any] = [
            "_recordType": record.recordType,
            "_recordId": record.recordID.recordName
        ]

        // Extract all fields
        for key in record.allKeys() {
            if let asset = record[key] as? CKAsset, let url = asset.fileURL {
                // Handle embedding asset
                if let binaryData = try? Data(contentsOf: url) {
                    data[key] = FlutterStandardTypedData(bytes: binaryData)
                }
            } else if let date = record[key] as? Date {
                data[key] = date.timeIntervalSince1970 * 1000
            } else {
                data[key] = record[key]
            }
        }

        // Send to Flutter
        eventSink?(["type": "recordFetched", "data": data])
    }

    private func handleDeletedRecord(_ recordID: CKRecord.ID) {
        eventSink?([
            "type": "recordDeleted",
            "recordId": recordID.recordName
        ])
    }

    // MARK: - Conflict Resolution

    private func handleSaveFailure(recordID: CKRecord.ID, error: CKSyncEngine.RecordZoneChangeBatch.FailedRecordSave) {
        switch error {
        case .serverRecordChanged(let serverRecord):
            // Server has newer version - merge or accept server
            resolveConflict(local: buildRecord(for: recordID), server: serverRecord)

        case .conflict(let serverRecord):
            resolveConflict(local: buildRecord(for: recordID), server: serverRecord)

        default:
            // Retry or notify Flutter of error
            eventSink?(["type": "syncError", "recordId": recordID.recordName, "error": String(describing: error)])
        }
    }

    private func resolveConflict(local: CKRecord?, server: CKRecord) {
        // Strategy: Server wins for LLM-generated fields, local wins for user data
        guard let local = local else {
            handleFetchedRecord(server)
            return
        }

        let merged = server

        // Preserve local user-modified fields if they're newer
        let localUpdatedAt = local["updatedAt"] as? Date ?? .distantPast
        let serverUpdatedAt = server["updatedAt"] as? Date ?? .distantPast

        // For notes and albums, prefer local if newer (user-generated content)
        if server.recordType == "Note" || server.recordType == "Album" {
            if localUpdatedAt > serverUpdatedAt {
                for key in local.allKeys() {
                    merged[key] = local[key]
                }
            }
        }

        // Re-queue the merged record
        let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(merged.recordID)
        syncEngine.state.add(pendingRecordZoneChanges: [change])

        // Also update local with server data
        handleFetchedRecord(merged)
    }
}
```

### 3. Flutter Plugin Bridge (Swift)

```swift
// ios/Runner/CloudKitPlugin.swift

import Flutter

class CloudKitPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let syncService = CloudKitSyncService()
    private var eventSink: FlutterEventSink?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = CloudKitPlugin()

        // Method channel for commands
        let methodChannel = FlutterMethodChannel(
            name: "com.photobrain/cloudkit",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        // Event channel for sync events
        let eventChannel = FlutterEventChannel(
            name: "com.photobrain/cloudkit_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterPlugin

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            syncService.initialize()
            result(nil)

        case "queueChange":
            guard let args = call.arguments as? [String: Any],
                  let recordType = args["recordType"] as? String,
                  let recordId = args["recordId"] as? String,
                  let data = args["data"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            syncService.queueRecordChange(recordType: recordType, recordId: recordId, data: data)
            result(nil)

        case "queueDeletion":
            guard let args = call.arguments as? [String: Any],
                  let recordType = args["recordType"] as? String,
                  let recordId = args["recordId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            syncService.queueRecordDeletion(recordType: recordType, recordId: recordId)
            result(nil)

        case "sync":
            syncService.triggerSync()
            result(nil)

        case "getAccountStatus":
            Task {
                let status = try? await CKContainer.default().accountStatus()
                result(status?.rawValue ?? -1)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        syncService.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        syncService.eventSink = nil
        return nil
    }
}
```

### 4. Register Plugin in AppDelegate

```swift
// ios/Runner/AppDelegate.swift

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Register CloudKit plugin
        if let controller = window?.rootViewController as? FlutterViewController {
            CloudKitPlugin.register(with: controller.registrar(forPlugin: "CloudKitPlugin")!)
        }

        // Enable remote notifications for CloudKit
        application.registerForRemoteNotifications()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit sends silent push notifications when data changes
        // CKSyncEngine handles this automatically
        completionHandler(.newData)
    }
}
```

---

## Flutter Implementation (Dart)

### 1. Sync Service Interface

```dart
// lib/services/sync/sync_service.dart

import 'dart:async';
import 'dart:io';

abstract class SyncService {
  Future<void> initialize();
  Future<void> queueChange(String table, String recordId, Map<String, dynamic> data);
  Future<void> queueDeletion(String table, String recordId);
  Future<void> sync();
  Stream<SyncEvent> get events;
  Future<SyncStatus> getStatus();
}

class SyncEvent {
  final SyncEventType type;
  final String? recordType;
  final String? recordId;
  final Map<String, dynamic>? data;
  final String? error;

  SyncEvent({
    required this.type,
    this.recordType,
    this.recordId,
    this.data,
    this.error,
  });

  factory SyncEvent.fromMap(Map<dynamic, dynamic> map) {
    return SyncEvent(
      type: SyncEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => SyncEventType.unknown,
      ),
      recordType: map['_recordType'],
      recordId: map['_recordId'] ?? map['recordId'],
      data: map['data'] != null ? Map<String, dynamic>.from(map['data']) : null,
      error: map['error'],
    );
  }
}

enum SyncEventType {
  recordFetched,
  recordDeleted,
  syncStarted,
  syncCompleted,
  syncError,
  progressUpdate,
  unknown,
}

enum SyncStatus { idle, syncing, error, offline }
```

### 2. iOS CloudKit Implementation

```dart
// lib/services/sync/cloudkit_sync_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'sync_service.dart';

class CloudKitSyncService implements SyncService {
  static const _methodChannel = MethodChannel('com.photobrain/cloudkit');
  static const _eventChannel = EventChannel('com.photobrain/cloudkit_events');

  final _eventController = StreamController<SyncEvent>.broadcast();
  StreamSubscription? _eventSubscription;

  @override
  Future<void> initialize() async {
    await _methodChannel.invokeMethod('initialize');

    // Listen to native events
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen((event) {
      if (event is Map) {
        _eventController.add(SyncEvent.fromMap(event));
      }
    });
  }

  @override
  Future<void> queueChange(
    String table,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final recordType = _tableToRecordType(table);

    await _methodChannel.invokeMethod('queueChange', {
      'recordType': recordType,
      'recordId': recordId,
      'data': {
        '_recordType': recordType,
        ...data,
      },
    });
  }

  @override
  Future<void> queueDeletion(String table, String recordId) async {
    await _methodChannel.invokeMethod('queueDeletion', {
      'recordType': _tableToRecordType(table),
      'recordId': recordId,
    });
  }

  @override
  Future<void> sync() async {
    await _methodChannel.invokeMethod('sync');
  }

  @override
  Stream<SyncEvent> get events => _eventController.stream;

  @override
  Future<SyncStatus> getStatus() async {
    final accountStatus = await _methodChannel.invokeMethod<int>('getAccountStatus');
    switch (accountStatus) {
      case 1: // available
        return SyncStatus.idle;
      case 2: // restricted
      case 3: // noAccount
        return SyncStatus.offline;
      default:
        return SyncStatus.error;
    }
  }

  String _tableToRecordType(String table) {
    switch (table) {
      case 'photos':
        return 'Photo';
      case 'metadata_llm':
        return 'PhotoMetadata';
      case 'notes':
        return 'Note';
      case 'albums':
        return 'Album';
      case 'embeddings_sync':
        return 'Embedding';
      default:
        return table;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventController.close();
  }
}
```

### 3. Database Service with Sync Integration

```dart
// lib/services/database_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'sync/sync_service.dart';

class DatabaseService {
  late Database _db;
  late SyncService _syncService;

  Future<void> initialize(SyncService syncService) async {
    _syncService = syncService;

    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'photobrain.db'),
      version: 1,
      onCreate: _createTables,
    );

    // Listen for remote changes
    _syncService.events.listen(_handleSyncEvent);
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source TEXT NOT NULL,
        capture_date INTEGER,
        latitude REAL,
        longitude REAL,
        location_name TEXT,
        file_hash TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE metadata_llm (
        photo_id TEXT PRIMARY KEY,
        description TEXT,
        objects TEXT,
        tags TEXT,
        mood TEXT,
        scene_type TEXT,
        text_detected TEXT,
        analysis_version TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        photo_ids TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE embeddings_sync (
        photo_id TEXT PRIMARY KEY,
        embedding BLOB NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Indexes for search
    await db.execute('CREATE INDEX idx_photos_capture_date ON photos(capture_date)');
    await db.execute('CREATE INDEX idx_photos_source_id ON photos(source_id)');
    await db.execute('CREATE INDEX idx_notes_photo_id ON notes(photo_id)');
  }

  // MARK: - Photo CRUD with Sync

  Future<void> insertPhoto(Map<String, dynamic> photo) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    photo['created_at'] = now;
    photo['updated_at'] = now;
    photo['sync_status'] = 'pending';

    await _db.insert('photos', photo);

    // Queue for sync
    await _syncService.queueChange('photos', photo['id'], photo);
  }

  Future<void> updatePhoto(String id, Map<String, dynamic> updates) async {
    updates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    updates['sync_status'] = 'pending';

    await _db.update('photos', updates, where: 'id = ?', whereArgs: [id]);

    // Get full record for sync
    final photo = await _db.query('photos', where: 'id = ?', whereArgs: [id]);
    if (photo.isNotEmpty) {
      await _syncService.queueChange('photos', id, photo.first);
    }
  }

  Future<void> deletePhoto(String id) async {
    await _db.delete('photos', where: 'id = ?', whereArgs: [id]);
    await _db.delete('metadata_llm', where: 'photo_id = ?', whereArgs: [id]);
    await _db.delete('embeddings_sync', where: 'photo_id = ?', whereArgs: [id]);

    await _syncService.queueDeletion('photos', id);
  }

  // MARK: - Embedding Storage

  Future<void> saveEmbedding(String photoId, List<double> embedding) async {
    // Convert to bytes (Float32)
    final bytes = Float32List.fromList(embedding.map((e) => e.toDouble()).toList());
    final blob = bytes.buffer.asUint8List();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.insert(
      'embeddings_sync',
      {
        'photo_id': photoId,
        'embedding': blob,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Queue for sync
    await _syncService.queueChange('embeddings_sync', photoId, {
      'photo_id': photoId,
      'embedding': blob,
      'updated_at': now,
    });

    // Also insert into vec table for local search
    await _rebuildVectorEntry(photoId, embedding);
  }

  Future<void> _rebuildVectorEntry(String photoId, List<double> embedding) async {
    // This requires sqlite-vec FFI - simplified here
    // In real implementation, use sqlite3 package with vec extension
    await _db.execute(
      'INSERT OR REPLACE INTO vec_embeddings (photo_id, embedding) VALUES (?, ?)',
      [photoId, embedding],
    );
  }

  // MARK: - Handle Remote Sync Events

  Future<void> _handleSyncEvent(SyncEvent event) async {
    switch (event.type) {
      case SyncEventType.recordFetched:
        await _applyRemoteChange(event);
        break;
      case SyncEventType.recordDeleted:
        await _applyRemoteDeletion(event);
        break;
      default:
        break;
    }
  }

  Future<void> _applyRemoteChange(SyncEvent event) async {
    if (event.data == null || event.recordType == null) return;

    final table = _recordTypeToTable(event.recordType!);
    final data = Map<String, dynamic>.from(event.data!);

    // Remove CloudKit metadata
    data.remove('_recordType');
    data.remove('_recordId');

    // Handle embedding binary data
    if (table == 'embeddings_sync' && data['embedding'] is Uint8List) {
      // Keep as blob
    }

    final id = event.recordId ?? data['id'] ?? data['photo_id'];
    if (id == null) return;

    // Check if exists
    final existing = await _db.query(
      table,
      where: _primaryKeyColumn(table) + ' = ?',
      whereArgs: [id],
    );

    if (existing.isEmpty) {
      data['sync_status'] = 'synced';
      await _db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      // Compare timestamps, apply if remote is newer
      final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
      final remoteUpdatedAt = data['updated_at'] as int? ?? 0;

      if (remoteUpdatedAt >= localUpdatedAt) {
        data['sync_status'] = 'synced';
        await _db.update(
          table,
          data,
          where: _primaryKeyColumn(table) + ' = ?',
          whereArgs: [id],
        );
      }
    }

    // If embedding was updated, rebuild vector index
    if (table == 'embeddings_sync') {
      await _rebuildVectorIndexForPhoto(id);
    }
  }

  Future<void> _applyRemoteDeletion(SyncEvent event) async {
    if (event.recordId == null) return;

    // Delete from all related tables
    await _db.delete('photos', where: 'id = ?', whereArgs: [event.recordId]);
    await _db.delete('metadata_llm', where: 'photo_id = ?', whereArgs: [event.recordId]);
    await _db.delete('embeddings_sync', where: 'photo_id = ?', whereArgs: [event.recordId]);
    await _db.delete('notes', where: 'id = ?', whereArgs: [event.recordId]);
    await _db.delete('albums', where: 'id = ?', whereArgs: [event.recordId]);
  }

  Future<void> _rebuildVectorIndexForPhoto(String photoId) async {
    final embedding = await _db.query(
      'embeddings_sync',
      columns: ['embedding'],
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );

    if (embedding.isNotEmpty) {
      final blob = embedding.first['embedding'] as Uint8List;
      final floats = Float32List.view(blob.buffer).toList();
      await _rebuildVectorEntry(photoId, floats.map((e) => e.toDouble()).toList());
    }
  }

  String _recordTypeToTable(String recordType) {
    switch (recordType) {
      case 'Photo': return 'photos';
      case 'PhotoMetadata': return 'metadata_llm';
      case 'Note': return 'notes';
      case 'Album': return 'albums';
      case 'Embedding': return 'embeddings_sync';
      default: return recordType.toLowerCase();
    }
  }

  String _primaryKeyColumn(String table) {
    switch (table) {
      case 'metadata_llm':
      case 'embeddings_sync':
        return 'photo_id';
      default:
        return 'id';
    }
  }
}
```

### 4. Sync Provider (Riverpod)

```dart
// lib/providers/sync_provider.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync/sync_service.dart';
import '../services/sync/cloudkit_sync_service.dart';
import '../services/sync/google_drive_sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  if (Platform.isIOS) {
    return CloudKitSyncService();
  } else if (Platform.isAndroid) {
    return GoogleDriveSyncService();
  }
  throw UnsupportedError('Platform not supported');
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final syncService = ref.watch(syncServiceProvider);

  yield await syncService.getStatus();

  await for (final event in syncService.events) {
    if (event.type == SyncEventType.syncStarted) {
      yield SyncStatus.syncing;
    } else if (event.type == SyncEventType.syncCompleted) {
      yield SyncStatus.idle;
    } else if (event.type == SyncEventType.syncError) {
      yield SyncStatus.error;
    }
  }
});
```

---

## Vector Embedding Sync Details

### Embedding Serialization

```dart
// lib/utils/embedding_utils.dart

import 'dart:typed_data';

class EmbeddingUtils {
  /// Convert List<double> to binary blob (768 * 4 = 3072 bytes)
  static Uint8List serializeEmbedding(List<double> embedding) {
    final floats = Float32List.fromList(embedding.map((e) => e.toDouble()).toList());
    return floats.buffer.asUint8List();
  }

  /// Convert binary blob back to List<double>
  static List<double> deserializeEmbedding(Uint8List blob) {
    final floats = Float32List.view(blob.buffer);
    return floats.map((e) => e.toDouble()).toList();
  }

  /// Size calculation
  static int embeddingSize(int dimensions) => dimensions * 4; // Float32 = 4 bytes
  // 768 dimensions = 3072 bytes = ~3KB per photo
}
```

### Vector Index Rebuild Strategy

```dart
// lib/services/vector_service.dart

class VectorService {
  final Database _db;

  VectorService(this._db);

  /// Rebuild entire vector index from embeddings_sync table
  /// Call after initial sync or when index is corrupted
  Future<void> rebuildFullIndex() async {
    // Clear existing index
    await _db.execute('DELETE FROM vec_embeddings');

    // Batch insert from sync table
    final embeddings = await _db.query('embeddings_sync');

    final batch = _db.batch();
    for (final row in embeddings) {
      final photoId = row['photo_id'] as String;
      final blob = row['embedding'] as Uint8List;
      final floats = EmbeddingUtils.deserializeEmbedding(blob);

      batch.execute(
        'INSERT INTO vec_embeddings (photo_id, embedding) VALUES (?, ?)',
        [photoId, floats],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Rebuild index for single photo (after sync update)
  Future<void> rebuildForPhoto(String photoId) async {
    final result = await _db.query(
      'embeddings_sync',
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );

    if (result.isEmpty) {
      await _db.execute(
        'DELETE FROM vec_embeddings WHERE photo_id = ?',
        [photoId],
      );
      return;
    }

    final blob = result.first['embedding'] as Uint8List;
    final floats = EmbeddingUtils.deserializeEmbedding(blob);

    await _db.execute(
      'INSERT OR REPLACE INTO vec_embeddings (photo_id, embedding) VALUES (?, ?)',
      [photoId, floats],
    );
  }
}
```

---

## Android Implementation: Google Drive

(For brevity, the Android Kotlin implementation follows the same pattern as iOS. See the Google Drive section in the original plan for details.)

Key differences:
- Uses JSON files in `appDataFolder` instead of CKRecord
- Manual change log merging instead of CKSyncEngine
- OAuth flow via Google Sign-In

---

## Sync Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         LOCAL CHANGE                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. User edits photo metadata / adds note / creates album       │
│  2. DatabaseService.updatePhoto(id, data)                       │
│  3. Write to SQLite                                             │
│  4. SyncService.queueChange(table, id, data)                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PLATFORM CHANNEL                             │
│  MethodChannel.invokeMethod('queueChange', {...})               │
└─────────────────────────────────────────────────────────────────┘
                                │
            ┌───────────────────┴───────────────────┐
            ▼                                       ▼
┌───────────────────────┐             ┌───────────────────────┐
│   iOS: CKSyncEngine   │             │  Android: Drive API   │
│                       │             │                       │
│  • Add to pending     │             │  • Add to change log  │
│  • Engine schedules   │             │  • Upload on sync()   │
│  • Automatic retry    │             │  • Manual retry       │
└───────────────────────┘             └───────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLOUD STORAGE                           │
│  iOS: CloudKit Private Database                                 │
│  Android: Google Drive appDataFolder                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       REMOTE CHANGE                             │
│  (Another device uploads changes)                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  iOS: CKSyncEngine fetches changes automatically                │
│  Android: Drive API polls or triggered sync                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EVENT CHANNEL                              │
│  EventChannel sends SyncEvent.recordFetched to Flutter          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. DatabaseService._handleSyncEvent(event)                     │
│  2. Compare timestamps, resolve conflicts                       │
│  3. Update local SQLite                                         │
│  4. If embedding changed, rebuild vec_embeddings entry          │
│  5. Notify UI via Riverpod providers                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Checklist

### Phase 1: Foundation (Week 1)
- [ ] Create SQLite schema with all tables
- [ ] Set up sqlite-vec FFI integration
- [ ] Implement EmbeddingUtils serialization
- [ ] Create SyncService interface
- [ ] Set up platform channel structure

### Phase 2: iOS CloudKit (Week 2-3)
- [ ] Configure CloudKit container in Xcode
- [ ] Implement CloudKitSyncService (Swift)
- [ ] Implement CKSyncEngineDelegate
- [ ] Handle embedding as CKAsset
- [ ] Implement CloudKitPlugin bridge
- [ ] Test record creation/update/delete
- [ ] Test conflict resolution

### Phase 3: Flutter Integration (Week 3-4)
- [ ] Implement CloudKitSyncService (Dart)
- [ ] Integrate with DatabaseService
- [ ] Implement VectorService rebuild logic
- [ ] Create SyncProvider with Riverpod
- [ ] Build Sync Status UI widget
- [ ] Test full sync cycle

### Phase 4: Android Google Drive (Week 4-5)
- [ ] Configure Google Sign-In
- [ ] Implement GoogleDriveSyncService (Kotlin)
- [ ] Implement JSON change log system
- [ ] Handle embedding binary files
- [ ] Test sync on Android

### Phase 5: Polish (Week 5-6)
- [ ] Background sync (BGProcessingTask / WorkManager)
- [ ] Initial sync progress UI
- [ ] Error handling and retry logic
- [ ] Offline queue persistence
- [ ] Multi-device testing

---

## Sources

- [CKSyncEngine - Apple Documentation](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [WWDC23: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [Apple CloudKit Sync Engine Sample](https://github.com/apple/sample-cloudkit-sync-engine)
- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec)
- [sqflite Flutter Package](https://pub.dev/packages/sqflite)
- [Google Drive API v3](https://developers.google.com/drive/api/v3/about-sdk)

---

*Version: 2.0*
*Updated: January 2025*
*Focus: Record-level sync with CKSyncEngine*
