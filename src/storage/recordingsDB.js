const fs = require('fs');
const path = require('path');

class RecordingsDB {
    constructor() {
        this.dbPath = path.join(__dirname, '../../recordings.json');
        this.recordings = this.loadRecordings();
    }
    
    loadRecordings() {
        try {
            if (fs.existsSync(this.dbPath)) {
                const data = fs.readFileSync(this.dbPath, 'utf8');
                return JSON.parse(data);
            }
        } catch (error) {
            console.warn('failed to load recordings:', error.message);
        }
        return [];
    }
    
    saveRecordings() {
        try {
            fs.writeFileSync(this.dbPath, JSON.stringify(this.recordings, null, 2));
            return true;
        } catch (error) {
            console.error('failed to save recordings:', error.message);
            return false;
        }
    }
    
    addRecording(recordingData) {
        // Ensure the recording has all required UI fields
        const processedRecording = {
            ...recordingData,
            id: recordingData.sessionId || recordingData.id,
            title: recordingData.title || `meeting ${new Date(recordingData.timestamp).toLocaleDateString()}`,
            date: recordingData.date || new Date(recordingData.timestamp).toLocaleDateString(),
            time: recordingData.time || new Date(recordingData.timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}),
            duration: recordingData.duration || (recordingData.durationSeconds ? this.formatDuration(recordingData.durationSeconds) : '0:00')
        };
        
        this.recordings.unshift(processedRecording);
        this.saveRecordings();
        return processedRecording;
    }
    
    formatDuration(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
    
    updateRecording(sessionId, updates) {
        const index = this.recordings.findIndex(r => r.sessionId === sessionId);
        if (index !== -1) {
            this.recordings[index] = { ...this.recordings[index], ...updates };
            this.saveRecordings();
            return this.recordings[index];
        }
        return null;
    }
    
    getAllRecordings() {
        return this.recordings;
    }
    
    getRecording(sessionId) {
        return this.recordings.find(r => r.sessionId === sessionId);
    }
}

module.exports = RecordingsDB;