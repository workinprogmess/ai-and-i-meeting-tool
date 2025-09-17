# ai&i utility scripts

these are standalone command-line tools for managing ai&i recordings and meetings. they are not part of the main app build.

## usage

run any script from the terminal:

```bash
cd Scripts
./script-name.swift
```

## available scripts

### backup-meetings.swift
backs up all meetings to timestamped folders
- keeps last 5 backups automatically
- creates manifest for easy recovery
- preserves metadata, transcripts, and audio

### restore-meetings.swift  
restores meetings from backup
- interactive selection of backup to restore
- prevents overwrites of existing files
- shows backup details before restoring

### recover-meetings.swift
recovers meetings with missing or corrupted transcripts
- regenerates transcripts from audio
- preserves original session metadata

### mix-audio.swift
manually mixes mic and system audio segments
- generates ffmpeg commands for perfect sync
- handles device switches and gaps

## notes

- scripts must be run from native directory or adjust paths
- requires read/write access to ~/Documents/ai&i-recordings
- backup location: ~/Documents/ai&i-backups