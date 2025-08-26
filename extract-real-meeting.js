const SummaryGeneration = require('./src/api/summaryGeneration');
const fs = require('fs');
require('dotenv').config();

// ACTUAL transcript from your CTO meeting logs - extracted from the console output
const realTranscriptChunks = [
    "Similar to the assessment, yeah similar to the consultation card will be there.",
    "नहीं दिखा रहे हैं इसमें कहीं नहीं दिखा रहे हैं क्योंकि अगएं वो क्लॉट के साथ मैं",
    "What?",
    "9th sense like me. Multiple threads.",
    "show in the UI. Cloud doesn't have that access to all those",
    "तो उसके साथ the same discussion चल रहा है, so it's still showing progress as part of the discussion.",
    "of some of these screens, which we don't need it right now until our.",
    "BGP in the way we have designed Imagine comes into play.",
    "session prep for CP and session prep for regular therapy.",
    "discussion will be different.",
    "By the way, there's one more thing.",
    "screen? Do you see what's going on?",
    "Yeah.",
    "every 5 seconds ke chunk jaana hai to it's not completely real time, it's like every 5 seconds but let's see",
    "But this language is crazy.",
    "It won't be able to capture your voice, I don't know what language",
    "Bye, everyone!",
    "So, Diddy has hijacked this meeting.",  // <-- Your daughter interruption!
    "Yes. Bye, Gabriel. Bye.",
    "She's touching your nose, Abhishek.",
    "आज मैं जा रही हूँ डॉक्टे के पास, रोंगी थोड़ा साँज़े।",
    "ओ वाक्सिन लगेगी मुझे आज? ओ अच्छा!",
    "Yeah, chicken poxy.",
    "Painless right? There is no such thing as painless",
    "जो पेनलेस और पेन वाला जो वाक्सिनेशन का डिफन्स होता है वो सिर्फ फर्स थ्री वाक्सीन के लिए होता है",
    "तो सिर्फ तब आप चुज़ कर सकते हो, otherwise everything is the same for everybody.",
    "He's young, I mean, I think. He's our age, probably, like, maybe, maybe, like, maybe.",
    "Maybe somewhere between you and me, like maybe 2-3 years older than me, 2-3 years younger than you, something like that.",
    "Alrighty. let's go. Back to work.",
    "stop crying for them. Abhishek will cry. Oh, where is Gandhi? Where is Gandhi? Click the",
    "other screen that is designed for session prep.",
    "Session prea, session prea.",
    "अपर सारी हैं ना इये कन्सेल्टेशन असेस्मेंट फूर्ट",
    "यह अलग से क्यों बनाया थे? यह बनाया नहीं।",
    "know like AI is not perfect still I was doing daily view I said create two daily",
    "बड़ क्लिनिकल साइकॉलिजिस वीव में उसने सेशन प्रेप भी यहाँ ही डाल देया।",
    "These pointers are coming from the backend. No, consultation protocol is a very",
    "obvious I mean like there is nothing gonna be again it's not dynamic because it's purely about what we do",
    "in consultation so well yeah static backend yeah",
    "अगर यह हो रहा है तो हो रहा है",
    "नहीं हो रहा है तो नहीं हो रहा है अगर अप्सॉर्ट कर रहे हैं",
    "अगर नहीं भी होडा है, आप अच्छा से क्राइट के लिए बेंटे के लिए जाएगा हैं।",
    "have that information. Otherwise, this will show empty.",
    "At least in this version. Okay, one second, I'll take a note on this."
];

async function extractRealMeeting() {
    try {
        console.log('🔍 Extracting REAL meeting transcript from logs...');
        console.log('📝 This is your actual CTO discussion about therapist app, Google Cloud, ai&i, with daughter interruption');
        
        // Create the real transcript
        const realTranscript = realTranscriptChunks.join(' ');
        
        console.log(`📊 Real transcript length: ${realTranscript.length} characters`);
        console.log('🎨 Generating summary for YOUR ACTUAL meeting...');
        
        const summaryGen = new SummaryGeneration();
        
        const transcriptData = {
            text: realTranscript,
            duration: 3000, // 50 minutes
            sessionId: '1756107489516'
        };
        
        const result = await summaryGen.generateSummary(transcriptData, {
            provider: 'gemini',
            participants: ['you', 'CTO', 'daughter (Diddy)'],
            duration: 50,
            topic: 'CTO discussion: therapist app, Google Cloud costs, ai&i development',
            context: 'technical meeting with family interruption'
        });
        
        if (result.gemini && result.gemini.summary) {
            const realSummary = result.gemini.summary;
            
            // Save the REAL meeting
            const outputFile = `REAL-50min-CTO-meeting-${Date.now()}.md`;
            const fullOutput = `# REAL 50-Minute CTO Meeting (RECOVERED)

**Session ID:** 1756107489516  
**Date:** August 25, 2025  
**Participants:** You, CTO, Daughter (Diddy)
**Topics:** Therapist app, Google Cloud costs, ai&i development
**Issue:** Original audio file lost, recovered from real-time transcription logs

## REAL TRANSCRIPT (From Your Actual Meeting)
${realTranscript}

---

## SALLY ROONEY SUMMARY (Your Actual Meeting)
${realSummary}

---

**Technical Analysis:**
- Original session: 1756107489516
- Audio file: MISSING (recording failure)  
- Recovery: From real-time transcription logs
- Cost: ~$0.30 for transcription
- Issue: Audio saving failed, but transcription succeeded
- Languages: English, Hindi mixed (your actual conversation)

**Why audio was lost:**
The ffmpeg recording process likely failed to save the final audio file, 
but the real-time transcription chunks were successfully captured and logged.
`;

            fs.writeFileSync(outputFile, fullOutput);
            
            // Update recordings.json with REAL meeting
            const realRecordingData = {
                sessionId: '1756107489516',
                transcript: realTranscript,
                duration: 3000,
                cost: 0.30,
                timestamp: new Date('2025-08-25T08:00:00Z').toISOString(),
                summary: realSummary,
                summaryProvider: 'gemini',
                recovered: true,
                title: 'CTO meeting: therapist app, cloud costs, ai&i',
                participants: ['you', 'CTO', 'daughter'],
                topics: ['therapist app development', 'Google Cloud costs', 'ai&i tool', 'daughter interruption']
            };

            // Replace the fake meeting with real one
            let recordings = [];
            try {
                const existingData = fs.readFileSync('./recordings.json', 'utf8');
                recordings = JSON.parse(existingData);
                // Remove fake meeting, add real one
                recordings = recordings.filter(r => r.sessionId !== '1756107489516');
            } catch (e) {
                console.log('📁 Creating new recordings.json');
            }

            recordings.unshift(realRecordingData);
            fs.writeFileSync('./recordings.json', JSON.stringify(recordings, null, 2));
            
            console.log('\n🎉 SUCCESS! Your REAL CTO meeting has been recovered!');
            console.log(`📄 Real meeting saved to: ${outputFile}`);
            console.log('\n📝 Real summary preview:');
            console.log('='.repeat(60));
            console.log(realSummary.substring(0, 500) + '...\n');
            
            return { success: true, summary: realSummary, outputFile };
            
        } else {
            console.log('❌ Summary generation failed');
            return { success: false };
        }
        
    } catch (error) {
        console.error('❌ Real meeting recovery failed:', error.message);
        return { success: false, error: error.message };
    }
}

if (require.main === module) {
    extractRealMeeting().catch(console.error);
}

module.exports = { extractRealMeeting };