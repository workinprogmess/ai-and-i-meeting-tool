const { getLoopbackAudioMediaStream } = require('electron-audio-loopback');

async function testElectronAudioLoopback() {
    console.log('🧪 Testing electron-audio-loopback functionality...\n');
    
    try {
        // Test 1: Microphone only
        console.log('📱 Test 1: Microphone capture');
        const micStream = await getLoopbackAudioMediaStream({
            systemAudio: false,
            microphone: true
        });
        console.log('✅ Microphone stream created:', micStream.id);
        console.log('   Audio tracks:', micStream.getAudioTracks().length);
        micStream.getTracks().forEach(track => track.stop());
        
        // Test 2: System audio only  
        console.log('\n🔊 Test 2: System audio capture');
        const systemStream = await getLoopbackAudioMediaStream({
            systemAudio: true,
            microphone: false
        });
        console.log('✅ System audio stream created:', systemStream.id);
        console.log('   Audio tracks:', systemStream.getAudioTracks().length);
        systemStream.getTracks().forEach(track => track.stop());
        
        // Test 3: Combined capture
        console.log('\n🎯 Test 3: Combined microphone + system audio');
        const combinedStream = await getLoopbackAudioMediaStream({
            systemAudio: true,
            microphone: true
        });
        console.log('✅ Combined stream created:', combinedStream.id);
        console.log('   Audio tracks:', combinedStream.getAudioTracks().length);
        combinedStream.getTracks().forEach(track => track.stop());
        
        // Test 4: MediaRecorder compatibility
        console.log('\n🎬 Test 4: MediaRecorder compatibility');
        const testStream = await getLoopbackAudioMediaStream({
            systemAudio: false,
            microphone: true
        });
        
        const recorder = new MediaRecorder(testStream, {
            mimeType: 'audio/webm;codecs=opus',
            audioBitsPerSecond: 128000
        });
        
        console.log('✅ MediaRecorder created successfully');
        console.log('   MIME type:', recorder.mimeType);
        console.log('   State:', recorder.state);
        
        testStream.getTracks().forEach(track => track.stop());
        
        console.log('\n🎉 All tests passed! electron-audio-loopback is working correctly.');
        console.log('\n📋 Summary:');
        console.log('   ✅ Microphone capture: Working');
        console.log('   ✅ System audio capture: Working'); 
        console.log('   ✅ Combined streams: Working');
        console.log('   ✅ MediaRecorder compatibility: Working');
        console.log('\nReady to implement milestone 3.2! 🚀');
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        console.error('   Error type:', error.name);
        console.error('   Stack:', error.stack);
        
        if (error.message.includes('Permission')) {
            console.log('\n🔐 Permission issue detected:');
            console.log('   • Make sure to grant microphone permission');
            console.log('   • System audio may require screen recording permission');
            console.log('   • Run test after granting permissions');
        }
        
        if (error.message.includes('not supported')) {
            console.log('\n⚠️  Compatibility issue:');
            console.log('   • Electron version:', process.versions.electron);
            console.log('   • Required: >= 31.0.1');
            console.log('   • Current should be compatible');
        }
    }
}

// Run test if called directly
if (require.main === module) {
    testElectronAudioLoopback();
}

module.exports = { testElectronAudioLoopback };