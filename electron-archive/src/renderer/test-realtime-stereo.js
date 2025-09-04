// Real-time stereo merge - the RIGHT way

async function createStereoStreamAtCapture(micStream, systemStream) {
    // Create audio context
    const audioContext = new AudioContext();
    const destination = audioContext.createMediaStreamDestination();
    
    // Create sources from streams
    const micSource = audioContext.createMediaStreamSource(micStream);
    const sysSource = audioContext.createMediaStreamSource(systemStream);
    
    // Create channel merger (2 inputs → stereo output)
    const merger = audioContext.createChannelMerger(2);
    
    // Connect: mic → left channel (0), system → right channel (1)
    micSource.connect(merger, 0, 0);  // mic to input 0
    sysSource.connect(merger, 0, 1);  // system to input 1
    
    // Connect merger to destination
    merger.connect(destination);
    
    // Return the STEREO STREAM (not audio buffers!)
    return destination.stream;
}

// Usage in startRecording:
async function startRecording() {
    const micStream = await navigator.mediaDevices.getUserMedia({audio: true});
    const systemStream = await getLoopbackAudioMediaStream();
    
    // Merge STREAMS in real-time (not files!)
    const stereoStream = await createStereoStreamAtCapture(micStream, systemStream);
    
    // Record the already-merged stereo stream
    const recorder = new MediaRecorder(stereoStream, {
        mimeType: 'audio/webm;codecs=opus'
    });
    
    // Now recording a SINGLE stereo file from the start!
    recorder.start();
}

// This creates ONE file with perfect alignment - no post-processing needed!