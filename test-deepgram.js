require('dotenv').config();
const SummaryGeneration = require('./src/api/summaryGeneration');

async function testDeepgram() {
    const summaryGen = new SummaryGeneration();
    
    // use the most recent recording pair
    const microphonePath = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_microphone.webm';
    const systemPath = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_system.webm';
    
    console.log('🧪 testing deepgram nova-3 with recording:');
    console.log(`microphone: ${microphonePath}`);
    console.log(`system: ${systemPath}`);
    
    try {
        // test separate file processing instead of stereo approach
        const result = await summaryGen.processWithDeepgramSeparate(microphonePath, systemPath, {
            testNote: 'testing 12:27 recording with separate file processing'
        });
        
        console.log('\n✅ deepgram test completed!');
        console.log(`transcript length: ${result.transcript.length} characters`);
        console.log(`cost: $${result.cost.totalCost.toFixed(4)}`);
        console.log(`duration: ${result.metadata.duration}s`);
        console.log(`channels: ${result.metadata.channels}`);
        
        // show first 500 chars of transcript
        console.log('\n📝 transcript preview:');
        console.log(result.transcript.substring(0, 500) + '...');
        
    } catch (error) {
        console.error('❌ deepgram test failed:', error.message);
        console.error('full error:', error);
    }
}

testDeepgram();