# Storage & Data Management Guidelines - ai&i

## core requirements
- **zero data loss**: recordings, transcripts, summaries are irreplaceable
- **atomic operations**: partial saves must not corrupt existing data
- **fast retrieval**: recordings list must load instantly on app startup
- **data integrity**: validate all saved data, handle corruption gracefully

## storage architecture
### file organization
- **recordings.json**: master index of all meeting sessions
- **audio-temp/**: temporary audio files during recording
- **transcripts/**: processed transcript files by session ID  
- **summaries/**: generated meeting summaries by session ID
- **backup strategy**: consider periodic exports for user data safety

### data format standards
- **consistent IDs**: sessionId used across all storage systems
- **timestamp normalization**: ISO strings for all date/time fields
- **UI compatibility**: include derived fields (date, time, duration) for display
- **metadata completeness**: participants, topic, context always captured

## competitive research
### how industry leaders handle data
- **granola**: local storage with cloud sync option for cross-device access
- **otter**: real-time cloud backup with offline fallback mechanisms
- **fireflies**: comprehensive metadata capture and search indexing

## recordingsDB implementation patterns
### data persistence requirements
```javascript
// required fields for UI compatibility
{
  id: sessionId,
  sessionId: unique_identifier,
  timestamp: ISO_string,
  date: "MM/DD/YYYY", 
  time: "HH:MM:SS AM/PM",
  duration: seconds_number,
  status: "completed" | "processing" | "failed",
  hasAudio: boolean,
  hasTranscript: boolean,
  hasSummary: boolean
}
```

### atomic operations
- **saveRecording()**: validate data before writing, rollback on failure
- **updateRecording()**: merge updates, preserve existing data
- **deleteRecording()**: clean up all related files (audio, transcript, summary)
- **export/import**: full data portability for user control

## error handling requirements
### data corruption scenarios
- **invalid JSON**: recover from malformed recordings.json with backup
- **missing files**: handle cases where audio exists but transcript missing
- **partial updates**: ensure UI shows accurate status of incomplete data
- **concurrent access**: prevent multiple processes corrupting same file

### recovery mechanisms
- **backup recordings.json**: keep previous version before each write
- **orphan file cleanup**: remove audio files not referenced in index
- **data validation**: verify file existence matches database records
- **repair functions**: fix common data inconsistencies automatically

## performance requirements
### loading speed benchmarks
- **app startup**: recordings list loads within 500ms
- **large datasets**: handle 100+ recordings without UI lag
- **search functionality**: quick filtering by date, participants, keywords
- **memory efficiency**: don't load full transcript data until requested

### scalability considerations
- **file size monitoring**: track storage usage, warn when disk space low
- **data archiving**: older recordings can be moved to compressed format
- **search indexing**: consider adding full-text search capabilities
- **sync preparation**: design data format for future cloud sync feature

## testing standards
### data integrity validation
- **round-trip testing**: save → load → verify all fields preserved
- **corruption simulation**: test recovery from various file corruption scenarios
- **concurrent operations**: multiple recordings happening simultaneously
- **edge cases**: very long meetings, special characters in metadata

### family context reliability
- **interruption resilience**: data saves must complete despite app backgrounding
- **child-proofing**: critical data operations protected from accidental deletion
- **multilingual metadata**: handle hindi/english mixed participant names
- **quick access patterns**: optimize for frequent review of recent meetings

## security considerations
### data protection standards
- **local-first**: sensitive meeting data stays on user's device
- **no cloud defaults**: explicit user consent required for any cloud features
- **access logging**: track when recordings are accessed for debugging
- **export controls**: secure data export without exposing system paths