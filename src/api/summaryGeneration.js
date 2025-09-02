const OpenAI = require('openai');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const fs = require('fs');
const path = require('path');

class SummaryGeneration {
    constructor() {
        // Only initialize what we actually use
        this.gemini = new GoogleGenerativeAI(process.env.GOOGLE_AI_KEY);
        
        // Initialize OpenAI only if we have the key (for backward compatibility)
        if (process.env.OPENAI_API_KEY) {
            this.openai = new OpenAI({
                apiKey: process.env.OPENAI_API_KEY
            });
        }
        
        // deterministic configuration for consistent transcription
        const deterministicConfig = {
            temperature: 0,
            topP: 0.1,
            topK: 1,
            maxOutputTokens: 8192
        };
        
        this.geminiModel = this.gemini.getGenerativeModel({ 
            model: 'gemini-1.5-pro',
            generationConfig: deterministicConfig
        });
        this.geminiFlashModel = this.gemini.getGenerativeModel({ 
            model: 'gemini-1.5-flash',
            generationConfig: deterministicConfig
        });
        
        this.loadPromptTemplates();
        this.summaryHistory = [];
    }
    
    loadPromptTemplates() {
        const frameworkPath = path.join(__dirname, '../../sally_rooney_prompt_framework.md');
        
        this.prompts = {
            gpt5: `you're writing a meeting summary in sally rooney's style - warm, observant, emotionally intelligent - but this is a real business meeting, not fiction.

meeting context:
- participants: {participants}
- duration: {duration} minutes
- topic: {topic}

your approach: capture what actually happened with sally rooney's warmth and insight. observe the human dynamics, but stick to what was said and done. no assumptions or invented details.

structure as separate paragraphs:
1. opening: who was there, the main topic, initial energy
2. key discussion points: each major topic gets its own paragraph  
3. decisions and agreements: what was actually decided
4. action items: who's doing what by when (use bullet points)

tone: conversational intimacy with business clarity. notice the emotional undercurrents but focus on the actual meeting content.

transcript:
{transcript}

write a meeting summary that feels human and perceptive while being genuinely useful for work.`,

            gemini: `write a meeting summary with sally rooney's warmth and emotional intelligence - but this is a real business meeting, not literary fiction.

meeting details:
- participants: {participants} 
- duration: {duration} minutes
- context: {context}

your approach: use sally rooney's observant, intimate tone to capture what actually happened. notice the human dynamics and emotional undercurrents, but ground everything in the real conversation.

structure as paragraphs:
1. meeting opening: who was present, the main issue on the table
2. key discussion points: each important topic in its own paragraph
3. decisions reached: what was actually agreed upon
4. action items: clear next steps with owners and deadlines (bullet format)

tone: conversational warmth with business substance. observe people's energy and interactions, but no invented details or assumptions.

transcript:
{transcript}

write a meeting summary that captures the human story while being genuinely useful for work follow-up.`
        };
    }
    
    async generateSummary(transcriptData, options = {}) {
        const {
            provider = 'both',
            participants = ['speaker 1', 'speaker 2'],
            duration = transcriptData.duration || 60,
            topic = 'team meeting',
            context = 'regular team check-in'
        } = options;
        
        console.log(`🎯 generating sally rooney-style summary with ${provider}...`);
        
        const transcript = this.formatTranscriptForSummary(transcriptData);
        const results = {};
        
        if (provider === 'gpt5' || provider === 'both') {
            try {
                console.log('📝 calling gpt-5...');
                results.gpt5 = await this.generateGPT5Summary(transcript, {
                    participants, duration, topic
                });
            } catch (error) {
                console.error('❌ gpt-5 failed:', error.message);
                results.gpt5 = { error: error.message };
            }
        }
        
        if (provider === 'gemini' || provider === 'both') {
            try {
                console.log('📝 calling gemini 2.5 pro...');
                results.gemini = await this.generateGeminiSummary(transcript, {
                    participants, duration, context
                });
            } catch (error) {
                console.error('❌ gemini 2.5 pro failed:', error.message);
                results.gemini = { error: error.message };
            }
        }
        
        // store for comparison
        const comparisonData = {
            timestamp: Date.now(),
            transcript: transcript.substring(0, 500) + '...',
            options,
            results
        };
        
        this.summaryHistory.push(comparisonData);
        await this.saveSummaryComparison(comparisonData);
        
        return results;
    }
    
    async generateGPT5Summary(transcript, metadata) {
        const prompt = this.prompts.gpt5
            .replace('{participants}', metadata.participants.join(', '))
            .replace('{duration}', metadata.duration)
            .replace('{topic}', metadata.topic)
            .replace('{transcript}', transcript);
        
        const startTime = Date.now();
        
        const response = await this.openai.chat.completions.create({
            model: 'gpt-5',
            messages: [
                {
                    role: 'system',
                    content: 'you are an expert at creating warm, emotionally intelligent meeting summaries in sally rooney\'s conversational style.'
                },
                {
                    role: 'user', 
                    content: prompt
                }
            ],
            max_completion_tokens: 4000
        });
        
        const processingTime = Date.now() - startTime;
        const summary = response.choices[0].message.content || '';
        
        // save individual gpt-5 summary
        await this.saveIndividualSummary('gpt5', summary, metadata, processingTime);
        
        return {
            provider: 'gpt-5',
            summary,
            cost: this.calculateCost('gpt5', prompt, summary),
            processingTime,
            tokenUsage: response.usage,
            timestamp: Date.now()
        };
    }
    
    async generateGeminiSummary(transcript, metadata) {
        const prompt = this.prompts.gemini
            .replace('{participants}', metadata.participants.join(', '))
            .replace('{duration}', metadata.duration)
            .replace('{context}', metadata.context)
            .replace('{transcript}', transcript);
        
        const startTime = Date.now();
        
        const result = await this.geminiModel.generateContent(prompt);
        const response = await result.response;
        const summary = response.text() || '';
        
        const processingTime = Date.now() - startTime;
        
        // save individual gemini summary  
        await this.saveIndividualSummary('gem15', summary, metadata, processingTime);
        
        return {
            provider: 'gemini-2.5-pro',
            summary,
            cost: this.calculateCost('gemini', prompt, summary),
            processingTime,
            tokenUsage: response.usageMetadata,
            timestamp: Date.now()
        };
    }
    
    formatTranscriptForSummary(transcriptData) {
        if (typeof transcriptData === 'string') {
            return transcriptData;
        }
        
        if (transcriptData.segments) {
            // format segments with speakers and timestamps
            return transcriptData.segments.map(segment => {
                const time = this.formatTime(segment.start || 0);
                const speaker = segment.speaker || 'speaker';
                const text = segment.text || segment.transcript || '';
                return `[${time}] ${speaker}: ${text}`;
            }).join('\n\n');
        }
        
        if (transcriptData.fullText) {
            return transcriptData.fullText;
        }
        
        return transcriptData.toString();
    }
    
    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
    
    calculateCost(provider, inputText, outputText) {
        const inputTokens = Math.ceil(inputText.length / 4); // rough estimate
        const outputTokens = Math.ceil(outputText.length / 4);
        
        const costs = {
            gpt5: { input: 1.25, output: 10.0 }, // per 1M tokens
            gemini: { input: 1.25, output: 10.0 }
        };
        
        const rates = costs[provider];
        return {
            inputTokens,
            outputTokens,
            inputCost: (inputTokens / 1000000) * rates.input,
            outputCost: (outputTokens / 1000000) * rates.output,
            totalCost: (inputTokens / 1000000) * rates.input + (outputTokens / 1000000) * rates.output
        };
    }
    
    async saveIndividualSummary(provider, summary, metadata, processingTime) {
        const summariesDir = path.join(__dirname, '../../summaries');
        if (!fs.existsSync(summariesDir)) {
            fs.mkdirSync(summariesDir, { recursive: true });
        }
        
        // create counter for naming
        const existingFiles = fs.readdirSync(summariesDir).filter(f => f.startsWith(`${provider}-`));
        const counter = existingFiles.length + 1;
        
        const summaryName = metadata.topic?.replace(/[^a-zA-Z0-9]/g, '').toLowerCase() || 'meeting';
        const filename = `${provider}-${summaryName}${counter}.md`;
        const filepath = path.join(summariesDir, filename);
        
        const content = `# ${metadata.topic || 'meeting summary'}\n\n**participants:** ${metadata.participants?.join(', ') || 'unknown'}\n**duration:** ${metadata.duration || 0} minutes\n**processed by:** ${provider}\n**processing time:** ${processingTime}ms\n\n---\n\n${summary}`;
        
        fs.writeFileSync(filepath, content);
        console.log(`💾 ${provider} summary saved to ${filename}`);
    }

    async saveSummaryComparison(comparisonData) {
        const summariesDir = path.join(__dirname, '../../summaries');
        if (!fs.existsSync(summariesDir)) {
            fs.mkdirSync(summariesDir, { recursive: true });
        }
        
        const filename = `summary_comparison_${comparisonData.timestamp}.json`;
        const filepath = path.join(summariesDir, filename);
        
        fs.writeFileSync(filepath, JSON.stringify(comparisonData, null, 2));
        console.log(`💾 summary comparison saved to ${filename}`);
    }
    
    async compareProviders(transcriptData, options = {}) {
        console.log('🔄 running side-by-side comparison of gpt-5 vs gemini 2.5 pro...');
        
        const results = await this.generateSummary(transcriptData, {
            ...options,
            provider: 'both'
        });
        
        const comparison = {
            gpt5: results.gpt5,
            gemini: results.gemini,
            analysis: this.analyzeSummaryQuality(results),
            recommendation: this.getProviderRecommendation(results)
        };
        
        console.log('\n📊 comparison results:');
        console.log(`gpt-5 cost: $${results.gpt5?.cost?.totalCost?.toFixed(4) || 'error'}`);
        console.log(`gemini cost: $${results.gemini?.cost?.totalCost?.toFixed(4) || 'error'}`);
        console.log(`recommendation: ${comparison.recommendation}`);
        
        return comparison;
    }
    
    analyzeSummaryQuality(results) {
        const analysis = {};
        
        for (const [provider, result] of Object.entries(results)) {
            if (result.error) {
                analysis[provider] = { error: result.error };
                continue;
            }
            
            const summary = result.summary;
            analysis[provider] = {
                length: summary.length,
                wordCount: summary.split(' ').length,
                hasSallyRooneyStyle: this.detectSallyRooneyStyle(summary),
                hasActionItems: this.detectActionItems(summary),
                emotionalIntelligence: this.detectEmotionalLanguage(summary),
                costEfficiency: result.cost.totalCost,
                speed: result.processingTime
            };
        }
        
        return analysis;
    }
    
    detectSallyRooneyStyle(text) {
        const indicators = [
            /you could (see|hear|feel)/i,
            /there was a (pause|moment|sense)/i,
            /(slowly|gradually|quietly)/i,
            /the kind of .* that/i,
            /voice (lifted|changed|softened)/i,
            /(energy|atmosphere|feeling) in the room/i
        ];
        
        return indicators.filter(pattern => pattern.test(text)).length;
    }
    
    detectActionItems(text) {
        const patterns = [
            /will (handle|take care of|work on)/i,
            /(deadline|due date|by \w+day)/i,
            /(assigned to|responsible for)/i,
            /(next steps?|action items?)/i
        ];
        
        return patterns.filter(pattern => pattern.test(text)).length;
    }
    
    detectEmotionalLanguage(text) {
        const emotional = [
            /excit(ed|ement|ing)/i,
            /(frustrat|concern|worry)/i,
            /(hesitat|uncertain|unsure)/i,
            /(energy|enthusiasm)/i,
            /(tension|strain|stress)/i,
            /(relief|satisfied|pleased)/i
        ];
        
        return emotional.filter(pattern => pattern.test(text)).length;
    }
    
    getProviderRecommendation(results) {
        if (results.gpt5?.error && !results.gemini?.error) return 'gemini-2.5-pro';
        if (results.gemini?.error && !results.gpt5?.error) return 'gpt-5';
        if (results.gpt5?.error && results.gemini?.error) return 'both failed';
        
        // compare based on quality indicators
        const gpt5Score = (results.gpt5?.cost?.totalCost < 0.05 ? 1 : 0) + 
                         (results.gpt5?.processingTime < 10000 ? 1 : 0);
        const geminiScore = (results.gemini?.cost?.totalCost < 0.05 ? 1 : 0) + 
                           (results.gemini?.processingTime < 10000 ? 1 : 0);
        
        return gpt5Score >= geminiScore ? 'gpt-5' : 'gemini-2.5-pro';
    }

    async processSingleStreamAudio(microphoneFilePath, systemAudioFilePath, context) {
        console.log('🎯 using single-stream processing approach...');
        const startTime = Date.now();
        
        try {
            // Process microphone and system audio separately
            const [micResult, systemResult] = await Promise.all([
                this.processIndividualStream(microphoneFilePath, '@me', 'microphone'),
                this.processIndividualStream(systemAudioFilePath, '@speaker', 'system')
            ]);
            
            console.log('🔍 micResult:', micResult ? 'exists' : 'missing');
            console.log('🔍 systemResult:', systemResult ? 'exists' : 'missing');
            
            // Merge the two transcripts chronologically
            const mergedTranscript = this.mergeTranscripts(micResult.transcript, systemResult.transcript);
            
            const processingTime = Date.now() - startTime;
            const totalCost = (micResult.cost || 0) + (systemResult.cost || 0);
            
            // Save individual streams and merged result for review
            const timestamp = Date.now();
            await this.saveSingleStreamResults({
                microphoneTranscript: micResult.transcript,
                systemTranscript: systemResult.transcript,
                mergedTranscript,
                timestamp,
                processingTime,
                totalCost
            });
            
            console.log(`✅ single-stream processing complete: ${processingTime}ms, $${totalCost.toFixed(4)}`);
            
            return {
                transcript: mergedTranscript,
                summary: 'single-stream processing (no summary generated)',
                speakerAnalysis: 'integrated into transcript',
                emotionalDynamics: 'single-stream approach',
                cost: { totalCost },
                processingTime,
                timestamp: Date.now(),
                provider: 'gemini-2.5-flash-single-stream'
            };
            
        } catch (error) {
            console.error('❌ single-stream processing failed:', error.message);
            throw error;
        }
    }

    async processIndividualStream(audioFilePath, speakerPrefix, streamType) {
        console.log(`🎤 processing ${streamType} stream:`, audioFilePath);
        
        try {
            const audioBuffer = await fs.promises.readFile(audioFilePath);
            const prompt = `transcribe this ${streamType} audio completely with timestamps.

REQUIREMENTS:
- add timestamp [MM:SS] at every speaker change or natural pause
- use ${speakerPrefix} for all speakers (${streamType === 'system' ? 'if multiple speakers, use @speaker1, @speaker2, etc' : ''})
- format: [MM:SS] ${speakerPrefix}: what was said
- capture every single word spoken
- maintain chronological order

example output:
[00:00] ${speakerPrefix}: opening statement here
[01:30] ${speakerPrefix}: continuing the conversation
[02:15] ${speakerPrefix}: final thoughts

transcribe from start to finish.`;

            const contentArray = [
                { text: prompt },
                {
                    inlineData: {
                        data: audioBuffer.toString('base64'),
                        mimeType: 'audio/webm'
                    }
                }
            ];

            const generationConfig = {
                temperature: 0,
                topP: 0.1,
                topK: 1,
                maxOutputTokens: 32768,
                seed: Math.floor(Date.now() / 1000)
            };

            const startTime = Date.now();
            const result = await this.geminiModel.generateContent({
                contents: [{ parts: contentArray }],
                generationConfig
            });

            const response = result.response;
            const transcript = response.text();
            const processingTime = Date.now() - startTime;
            
            console.log(`✅ ${streamType} stream complete: ${processingTime}ms`);
            
            // Calculate cost from usage metadata
            const inputTokens = response.usageMetadata?.promptTokenCount || 0;
            const outputTokens = response.usageMetadata?.candidatesTokenCount || 0;
            const cost = (inputTokens * 0.000000125) + (outputTokens * 0.000000375); // Gemini Flash pricing
            
            return {
                transcript: transcript.trim(),
                cost: cost,
                processingTime
            };
        } catch (error) {
            console.error(`❌ ${streamType} stream failed:`, error.message);
            throw error;
        }
    }

    mergeTranscripts(micTranscript, systemTranscript) {
        console.log('🔄 merging transcripts chronologically...');
        
        // Parse timestamps from both transcripts
        const micEntries = this.parseTimestampEntries(micTranscript);
        const systemEntries = this.parseTimestampEntries(systemTranscript);
        
        // Combine and sort by timestamp
        const allEntries = [...micEntries, ...systemEntries];
        allEntries.sort((a, b) => a.seconds - b.seconds);
        
        // Rebuild transcript
        const merged = allEntries.map(entry => `${entry.timestamp} ${entry.speaker}: ${entry.content}`).join('\n\n');
        
        console.log(`✅ merged ${micEntries.length + systemEntries.length} entries`);
        return merged;
    }

    parseTimestampEntries(transcript) {
        const entries = [];
        if (!transcript || typeof transcript !== 'string') {
            console.log('⚠️  empty or invalid transcript provided');
            return entries;
        }
        const lines = transcript.split('\n');
        
        for (const line of lines) {
            const match = line.match(/\[(\d{1,2}):(\d{2})\]\s*(@\w+):\s*(.+)/);
            if (match) {
                const [, minutes, seconds, speaker, content] = match;
                const totalSeconds = parseInt(minutes) * 60 + parseInt(seconds);
                entries.push({
                    timestamp: `[${minutes.padStart(2, '0')}:${seconds}]`,
                    speaker: speaker,
                    content: content.trim(),
                    seconds: totalSeconds
                });
            }
        }
        
        return entries;
    }

    async saveSingleStreamResults(results) {
        const { microphoneTranscript, systemTranscript, mergedTranscript, timestamp, processingTime, totalCost } = results;
        
        // Save individual stream transcripts
        const micFile = path.join(__dirname, '../../summaries', `microphone-stream-${timestamp}.md`);
        const systemFile = path.join(__dirname, '../../summaries', `system-stream-${timestamp}.md`);
        const mergedFile = path.join(__dirname, '../../summaries', `single-stream-merged-${timestamp}.md`);
        
        const micContent = `# microphone stream transcript - single-stream processing

**processing time:** ${processingTime}ms
**cost:** $${totalCost.toFixed(4)}
**timestamp:** ${timestamp}

---

${microphoneTranscript}`;

        const systemContent = `# system stream transcript - single-stream processing

**processing time:** ${processingTime}ms
**cost:** $${totalCost.toFixed(4)}
**timestamp:** ${timestamp}

---

${systemTranscript}`;

        const mergedContent = `# merged transcript - single-stream processing

**processing time:** ${processingTime}ms
**cost:** $${totalCost.toFixed(4)}
**timestamp:** ${timestamp}
**entries merged:** ${mergedTranscript.split('\n\n').length}

---

${mergedTranscript}`;

        await fs.promises.writeFile(micFile, micContent);
        await fs.promises.writeFile(systemFile, systemContent);
        await fs.promises.writeFile(mergedFile, mergedContent);
        
        console.log(`💾 single-stream files saved: microphone-stream-${timestamp}.md, system-stream-${timestamp}.md, single-stream-merged-${timestamp}.md`);
    }

    // gemini 2.5 flash end-to-end: audio → transcript + summary + speaker labels
    async processAudioEndToEnd(audioFilePath, options = {}) {
        const {
            participants = 'unknown participants',
            expectedDuration = 60,
            meetingTopic = 'business meeting',
            context = 'team discussion',
            systemAudioFilePath = null  // optional second audio file
        } = options;

        console.log(`🎯 gemini 2.5 flash end-to-end processing`);
        
        try {
            const fs = require('fs').promises;
            
            // prepare audio inputs based on what's available
            const audioInputs = [];
            
            // handle primary audio file (microphone or combined)
            if (audioFilePath) {
                console.log(`🎤 loading microphone audio: ${audioFilePath}`);
                const micBuffer = await fs.readFile(audioFilePath);
                audioInputs.push({
                    text: "MICROPHONE AUDIO (primary speaker = @me): this is the person conducting the test, speaking directly into microphone with AirPods. THIS VOICE SHOULD ALWAYS BE LABELED @me, never @speaker1 or @speaker2."
                });
                audioInputs.push({
                    inlineData: {
                        data: micBuffer.toString('base64'),
                        mimeType: 'audio/webm'
                    }
                });
            }
            
            // handle system audio file if provided (two-file approach)
            if (systemAudioFilePath) {
                console.log(`🔊 loading system audio: ${systemAudioFilePath}`);
                const systemBuffer = await fs.readFile(systemAudioFilePath);
                audioInputs.push({
                    text: "SYSTEM AUDIO (YouTube/video speakers = @speaker1, @speaker2, etc): this contains voices from videos/calls played through system audio, NOT the microphone speaker. These should be labeled @speaker1, @speaker2, never @me."
                });
                audioInputs.push({
                    inlineData: {
                        data: systemBuffer.toString('base64'),
                        mimeType: 'audio/webm'
                    }
                });
            }

        // Check if we should use single-stream processing
        if (systemAudioFilePath && process.env.USE_SINGLE_STREAM_PROCESSING === 'true') {
            console.log('🔄 switching to single-stream processing...');
            return await this.processSingleStreamAudio(audioFilePath, systemAudioFilePath, context);
        }

        // Original dual-stream processing
        const prompt = `transcribe this audio recording completely, capturing every word spoken.

CONVERSATION FLOW APPROACH:
i'm providing ${audioInputs.length / 2} audio file(s) that contain a natural conversation:
- MICROPHONE AUDIO (primary speaker = @me): this is the person conducting the meeting/test
${systemAudioFilePath ? `- SYSTEM AUDIO (other participants = @speaker1, @speaker2, etc): voices from videos, calls, or other participants` : ''}

CRITICAL SPEAKER IDENTIFICATION:
- @me = ALWAYS the person conducting the meeting/test (the primary user)
- This voice should ALWAYS be labeled @me throughout the entire recording
- Even if audio device changes (AirPods on/off, microphone switching), the same person = @me
- @speaker1, @speaker2, etc = any OTHER people's voices (from calls, videos, other participants)
- NEVER change @me to @speaker1 or @speaker2 during the conversation
- The person who started the recording remains @me for the full duration

NATURAL CONVERSATION CAPTURE:
- transcribe exactly what was said as the conversation flowed
- follow natural speaker transitions - when one person stops, another begins
- capture ALL speech content - don't skip any segments due to audio quality
- maintain conversation rhythm - pauses, interruptions, overlapping speech
- NO timestamps needed - focus entirely on capturing complete content
- include every word spoken by every participant

REQUIREMENTS:
- transcribe speaker by speaker, line by line, as it ebbed and flowed naturally
- start each speaker statement with @me: or @speaker1: etc
- new line for each speaker change or major thought
- capture 100% of spoken content - every single word matters
- if audio quality is poor, transcribe what you can hear rather than skipping
- maintain proper formatting throughout
- just accurate, complete transcription - no analysis or emotions

format example:
@me: what they said here
@speaker1: their response goes here  
@me: my follow-up comment

transcribe the complete conversation from start to finish.`;

            const startTime = Date.now();
            
            // build content array with original prompt and audio inputs
            const contentArray = [{ text: prompt }, ...audioInputs];
            
            // add simple deterministic config
            const generationConfig = {
                temperature: 0,
                topP: 0.1,
                topK: 1,
                maxOutputTokens: 32768, // high limit for long meetings
                seed: Math.floor(Date.now() / 1000) // daily seed for consistency within same day
            };
            
            console.log(`📤 sending ${audioInputs.length / 2} audio file(s) to gemini with simple deterministic config...`);
            const result = await this.geminiFlashModel.generateContent(contentArray, { generationConfig });
            
            const response = await result.response;
            const fullOutput = response.text();
            const processingTime = Date.now() - startTime;

            // parse the structured output (now includes reasoning section)
            const sections = this.parseGeminiEndToEndOutput(fullOutput);
            
            const result_data = {
                provider: 'gemini-2.5-flash-end-to-end',
                fullOutput,
                transcript: sections.transcript,
                summary: sections.summary,
                speakerAnalysis: sections.speakerAnalysis,
                emotionalDynamics: sections.emotionalDynamics,
                cost: this.calculateCost('gemini', prompt, fullOutput),
                processingTime,
                tokenUsage: response.usageMetadata,
                timestamp: Date.now(),
                audioFilePath
            };

            // save results
            await this.saveEndToEndResult(result_data, options);
            
            console.log(`✅ gemini end-to-end complete: ${processingTime}ms, $${result_data.cost.totalCost.toFixed(4)}`);
            
            return result_data;

        } catch (error) {
            console.error('❌ gemini end-to-end failed:', error.message);
            return {
                provider: 'gemini-2.5-flash-end-to-end',
                error: error.message,
                timestamp: Date.now(),
                audioFilePath
            };
        }
    }

    parseGeminiEndToEndOutput(fullOutput) {
        const sections = {
            transcript: '',
            summary: '',
            speakerAnalysis: '',
            emotionalDynamics: ''
        };

        try {
            // check if this is our natural conversation format (starts with @speaker)
            const naturalConversationPattern = /^\s*@\w+:/;
            if (naturalConversationPattern.test(fullOutput)) {
                // this is our natural conversation format - use it as-is
                sections.transcript = fullOutput;
                sections.summary = 'transcript-only mode (no summary requested)';
                sections.speakerAnalysis = 'integrated into transcript';
                sections.emotionalDynamics = 'natural conversation flow';
                return sections;
            }
            
            // check if this is our simplified format (starts with timestamp like [00:00])
            const simpleTimestampPattern = /^\[?\d{1,2}:\d{2}\]?\s*@/;
            if (simpleTimestampPattern.test(fullOutput)) {
                // this is our simplified transcript format - use it as-is
                sections.transcript = fullOutput;
                sections.summary = 'transcript-only mode (no summary requested)';
                sections.speakerAnalysis = 'integrated into transcript';
                sections.emotionalDynamics = 'simplified format';
                return sections;
            }
            
            // otherwise try to parse complex format
            // extract transcript section - everything after first timestamp pattern
            const transcriptStartMatch = fullOutput.match(/\*\*\[[\d:\-]+\]/);
            if (transcriptStartMatch) {
                const transcriptStart = transcriptStartMatch.index;
                const summaryStart = fullOutput.indexOf('## summary');
                
                if (summaryStart > transcriptStart) {
                    sections.transcript = fullOutput.substring(transcriptStart, summaryStart).trim();
                } else {
                    sections.transcript = fullOutput.substring(transcriptStart).trim();
                }
            } else {
                // fallback to section after "## transcript"
                const transcriptMatch = fullOutput.match(/## transcript\s*([\s\S]*?)(?=## summary|$)/i);
                sections.transcript = transcriptMatch ? transcriptMatch[1].trim() : 'enhanced transcript parsing failed';
            }

            // extract summary section - everything after "## summary" 
            const summaryMatch = fullOutput.match(/## summary\s*([\s\S]*?)$/i);
            sections.summary = summaryMatch ? summaryMatch[1].trim() : 'enhanced summary parsing failed';

            // for enhanced format, speaker analysis and emotional dynamics are integrated into summary
            // extract them if they exist as separate sections
            const speakerMatch = fullOutput.match(/### part 2: relationship dynamics\s*([\s\S]*?)(?=### part 3|$)/i);
            const emotionalMatch = fullOutput.match(/\*\*energy\/mood:\*\*\s*([\s\S]*?)(?=\*\*|$)/i);

            sections.speakerAnalysis = speakerMatch ? speakerMatch[1].trim() : 'integrated into summary';
            sections.emotionalDynamics = emotionalMatch ? emotionalMatch[1].trim() : 'integrated into summary';

        } catch (error) {
            console.error('❌ failed to parse enhanced gemini output:', error.message);
            sections.transcript = fullOutput; // fallback to full output
        }

        return sections;
    }

    async saveEndToEndResult(resultData, options) {
        const summariesDir = path.join(__dirname, '../../summaries');
        if (!fs.existsSync(summariesDir)) {
            fs.mkdirSync(summariesDir, { recursive: true });
        }

        const timestamp = Date.now();
        const topicName = options.meetingTopic?.replace(/[^a-zA-Z0-9]/g, '').toLowerCase() || 'meeting';
        
        // save complete result
        const filename = `gemini-e2e-${topicName}-${timestamp}.json`;
        const filepath = path.join(summariesDir, filename);
        
        fs.writeFileSync(filepath, JSON.stringify(resultData, null, 2));
        
        // save human-readable transcript
        const transcriptFilename = `transcript-e2e-${topicName}-${timestamp}.md`;
        const transcriptPath = path.join(summariesDir, transcriptFilename);
        
        const transcriptContent = `# meeting transcript - gemini 2.5 flash end-to-end\n\n**audio file:** ${resultData.audioFilePath}\n**processing time:** ${resultData.processingTime}ms\n**cost:** $${resultData.cost?.totalCost?.toFixed(4)}\n\n---\n\n${resultData.transcript}`;
        
        fs.writeFileSync(transcriptPath, transcriptContent);
        
        // save human-readable summary  
        const summaryFilename = `summary-e2e-${topicName}-${timestamp}.md`;
        const summaryPath = path.join(summariesDir, summaryFilename);
        
        const summaryContent = `# meeting summary - gemini 2.5 flash end-to-end\n\n**participants:** ${options.participants || 'unknown'}\n**duration:** ${options.expectedDuration || 0} minutes\n**processed by:** gemini-2.5-flash-end-to-end\n**processing time:** ${resultData.processingTime}ms\n\n---\n\n${resultData.summary}\n\n## speaker analysis\n${resultData.speakerAnalysis}\n\n## emotional dynamics\n${resultData.emotionalDynamics}`;
        
        fs.writeFileSync(summaryPath, summaryContent);
        
        console.log(`💾 gemini end-to-end saved: ${filename}, ${transcriptFilename}, ${summaryFilename}`);
    }

    // compare pipelines: current (whisper → gemini) vs new (gemini end-to-end)
    async comparePipelines(audioFilePath, options = {}) {
        console.log('🔄 comparing pipeline a (whisper→gemini) vs pipeline b (gemini end-to-end)...');
        
        const startTime = Date.now();
        const results = {};

        // pipeline a: current approach (whisper → gemini)
        try {
            console.log('🎵 pipeline a: whisper → gemini summary...');
            
            // would need to call whisper first, then pass transcript to existing generateSummary
            // for now, simulate or use existing transcript if available
            results.pipelineA = {
                provider: 'whisper-transcription + gemini-summary',
                status: 'needs whisper integration',
                note: 'requires whisper api call first'
            };
            
        } catch (error) {
            results.pipelineA = { error: error.message };
        }

        // pipeline b: gemini end-to-end  
        try {
            console.log('🎯 pipeline b: gemini 2.5 flash end-to-end...');
            results.pipelineB = await this.processAudioEndToEnd(audioFilePath, options);
            
        } catch (error) {
            results.pipelineB = { error: error.message };
        }

        const totalTime = Date.now() - startTime;
        
        const comparison = {
            timestamp: Date.now(),
            audioFilePath,
            totalProcessingTime: totalTime,
            pipelineA: results.pipelineA,
            pipelineB: results.pipelineB,
            recommendation: this.getPipelineRecommendation(results)
        };

        // save comparison
        const comparisonFilename = `pipeline_comparison_${comparison.timestamp}.json`;
        const comparisonPath = path.join(__dirname, '../../summaries', comparisonFilename);
        fs.writeFileSync(comparisonPath, JSON.stringify(comparison, null, 2));
        
        console.log('📊 pipeline comparison results:');
        console.log(`pipeline a status: ${results.pipelineA.status || 'error'}`);
        console.log(`pipeline b cost: $${results.pipelineB?.cost?.totalCost?.toFixed(4) || 'error'}`);
        console.log(`recommendation: ${comparison.recommendation}`);
        
        return comparison;
    }

    getPipelineRecommendation(results) {
        // if pipeline b worked and pipeline a didn't, recommend b
        if (results.pipelineB && !results.pipelineB.error && results.pipelineA.error) {
            return 'pipeline b (gemini end-to-end)';
        }
        
        // if both worked, compare based on criteria
        if (results.pipelineB && !results.pipelineB.error) {
            return 'pipeline b (gemini end-to-end) - single api call, speaker identification, emotional context';
        }
        
        return 'pipeline a (whisper → gemini) - proven approach';
    }

    // deepgram nova-3 separate file processing (like gemini approach)
    async processWithDeepgramSeparate(microphoneFilePath, systemAudioFilePath, context = {}) {
        console.log('🎯 using deepgram nova-3 with separate file processing...');
        const startTime = Date.now();
        
        try {
            // process each file separately
            console.log('🎤 processing microphone audio...');
            const micResult = await this.callDeepgramAPI(microphoneFilePath, {
                model: 'nova-3',
                smart_format: true,
                diarize: true,
                punctuate: true,
                profanity_filter: false,
                redact: false
            });
            
            console.log('🔊 processing system audio...');
            const systemResult = await this.callDeepgramAPI(systemAudioFilePath, {
                model: 'nova-3', 
                smart_format: true,
                diarize: true,
                punctuate: true,
                profanity_filter: false,
                redact: false
            });
            
            const processingTime = Date.now() - startTime;
            
            // calculate combined cost
            const micCost = this.calculateDeepgramCost(micResult.metadata.duration);
            const systemCost = this.calculateDeepgramCost(systemResult.metadata.duration);
            const totalCost = micCost + systemCost;
            
            // format transcripts with proper speaker labels
            const micTranscript = this.formatDeepgramTranscript(micResult, '@me');
            const systemTranscript = this.formatDeepgramTranscript(systemResult, '@speaker');
            
            // simple sequential merge (like early gemini approach)
            const combinedTranscript = `${micTranscript}\n\n---\n\n${systemTranscript}`;
            
            const result = {
                transcript: combinedTranscript,
                processingTime,
                cost: {
                    totalCost: totalCost,
                    microphoneCost: micCost,
                    systemCost: systemCost,
                    service: 'deepgram-nova-3-separate'
                },
                metadata: {
                    microphoneDuration: micResult.metadata.duration,
                    systemDuration: systemResult.metadata.duration,
                    model: 'nova-3'
                },
                sourceFiles: {
                    microphone: microphoneFilePath,
                    system: systemAudioFilePath
                },
                rawResults: {
                    microphone: micResult,
                    system: systemResult
                }
            };
            
            // save result
            await this.saveDeepgramResult(result, context);
            
            console.log(`✅ deepgram separate processing completed in ${processingTime}ms, total cost: $${totalCost.toFixed(4)}`);
            return result;
            
        } catch (error) {
            console.error('❌ deepgram separate processing failed:', error.message);
            throw error;
        }
    }

    // deepgram nova-3 stereo multichannel transcription integration
    async processWithDeepgramNova3(microphoneFilePath, systemAudioFilePath, context = {}) {
        console.log('🎯 using deepgram nova-3 with stereo multichannel audio...');
        const startTime = Date.now();
        
        try {
            // create stereo webm file: left=mic, right=system
            const stereoAudioPath = await this.createMultiChannelAudio(microphoneFilePath, systemAudioFilePath);
            
            // transcribe with deepgram nova-3 multichannel
            const transcriptResult = await this.callDeepgramAPI(stereoAudioPath, {
                model: 'nova-3',
                smart_format: true,
                diarize: true,
                multichannel: true,  // enable multichannel processing
                punctuate: true,
                profanity_filter: false,
                redact: false
            });
            
            const processingTime = Date.now() - startTime;
            const cost = this.calculateDeepgramCost(transcriptResult.metadata.duration);
            
            // format transcript in our natural conversation format
            const formattedTranscript = this.formatDeepgramTranscript(transcriptResult);
            
            const result = {
                transcript: formattedTranscript,
                processingTime,
                cost: {
                    totalCost: cost,
                    service: 'deepgram-nova-3-stereo'
                },
                metadata: {
                    duration: transcriptResult.metadata.duration,
                    channels: transcriptResult.metadata.channels,
                    model: 'nova-3'
                },
                audioFilePath: stereoAudioPath,
                sourceFiles: {
                    microphone: microphoneFilePath,
                    system: systemAudioFilePath
                }
            };
            
            // save result
            await this.saveDeepgramResult(result, context);
            
            console.log(`✅ deepgram nova-3 completed in ${processingTime}ms, cost: $${cost.toFixed(4)}`);
            return result;
            
        } catch (error) {
            console.error('❌ deepgram nova-3 processing failed:', error.message);
            throw error;
        }
    }
    
    async createMultiChannelAudio(microphoneFilePath, systemAudioFilePath) {
        const ffmpeg = require('fluent-ffmpeg');
        const outputPath = microphoneFilePath.replace('.webm', '_stereo.webm');
        
        return new Promise((resolve, reject) => {
            ffmpeg()
                .input(microphoneFilePath)
                .input(systemAudioFilePath)
                .complexFilter([
                    '[0:a]pan=mono|c0=0.5*c0+0.5*c1[left]',   // mic to left channel
                    '[1:a]pan=mono|c0=0.5*c0+0.5*c1[right]',  // system to right channel  
                    '[left][right]amerge=inputs=2[out]'       // combine to stereo
                ])
                .outputOptions(['-map', '[out]'])
                .audioCodec('libopus')
                .audioChannels(2)
                .format('webm')
                .output(outputPath)
                .on('end', () => {
                    console.log(`✅ created stereo webm: ${outputPath}`);
                    resolve(outputPath);
                })
                .on('error', (error) => {
                    console.error('❌ ffmpeg stereo creation failed:', error);
                    reject(error);
                })
                .run();
        });
    }
    
    async callDeepgramAPI(audioFilePath, options = {}) {
        const fs = require('fs').promises;
        
        if (!process.env.DEEPGRAM_API_KEY) {
            throw new Error('DEEPGRAM_API_KEY environment variable is required');
        }
        
        const audioBuffer = await fs.readFile(audioFilePath);
        
        // build query parameters
        const params = new URLSearchParams({
            model: options.model || 'nova-3',
            smart_format: options.smart_format || true,
            diarize: options.diarize || true,
            multichannel: options.multichannel || true,
            punctuate: options.punctuate || true,
            profanity_filter: options.profanity_filter || false,
            redact: options.redact || false
        });
        
        const url = `https://api.deepgram.com/v1/listen?${params}`;
        
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Authorization': `Token ${process.env.DEEPGRAM_API_KEY}`,
                'Content-Type': 'audio/wav',
            },
            body: audioBuffer
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`deepgram api error: ${response.status} ${errorText}`);
        }
        
        const result = await response.json();
        console.log(`✅ deepgram api success: ${result.metadata.duration}s, ${result.metadata.channels} channels`);
        
        return result;
    }
    
    formatDeepgramTranscript(deepgramResult, defaultSpeaker = null) {
        const alternatives = deepgramResult.results?.channels?.[0]?.alternatives?.[0];
        if (!alternatives) {
            throw new Error('no transcript alternatives found in deepgram response');
        }
        
        const words = alternatives.words || [];
        const transcript = alternatives.transcript;
        
        // if we have speaker diarization, format with speakers
        if (words.some(word => word.speaker !== undefined)) {
            return this.formatWithSpeakers(words, defaultSpeaker);
        }
        
        // fallback to simple transcript with default speaker if provided
        if (defaultSpeaker && transcript) {
            return `${defaultSpeaker}: ${transcript}`;
        }
        
        return transcript;
    }
    
    formatWithSpeakers(words, defaultSpeaker = null) {
        const lines = [];
        let currentSpeaker = null;
        let currentLine = '';
        
        for (const word of words) {
            const speaker = word.speaker;
            let speakerLabel;
            
            if (defaultSpeaker) {
                speakerLabel = defaultSpeaker;
            } else {
                speakerLabel = speaker === 0 ? '@me' : `@speaker${speaker}`;
            }
            
            if (currentSpeaker !== speaker) {
                // new speaker, finish previous line
                if (currentLine.trim()) {
                    const previousLabel = defaultSpeaker || (currentSpeaker === 0 ? '@me' : `@speaker${currentSpeaker}`);
                    lines.push(`${previousLabel}: ${currentLine.trim()}`);
                }
                
                // start new line
                currentSpeaker = speaker;
                currentLine = word.punctuated_word || word.word;
            } else {
                // same speaker, continue line
                currentLine += ' ' + (word.punctuated_word || word.word);
            }
        }
        
        // finish final line
        if (currentLine.trim()) {
            const finalLabel = defaultSpeaker || (currentSpeaker === 0 ? '@me' : `@speaker${currentSpeaker}`);
            lines.push(`${finalLabel}: ${currentLine.trim()}`);
        }
        
        return lines.join('\n\n');
    }
    
    calculateDeepgramCost(durationSeconds) {
        // deepgram nova-3 pricing: $0.26 per hour
        const pricePerHour = 0.26;
        const hours = durationSeconds / 3600;
        return hours * pricePerHour;
    }
    
    async saveDeepgramResult(resultData, context) {
        const summariesDir = path.join(__dirname, '../../summaries');
        if (!fs.existsSync(summariesDir)) {
            fs.mkdirSync(summariesDir, { recursive: true });
        }
        
        const timestamp = Date.now();
        
        // save complete result
        const filename = `deepgram-nova3-${timestamp}.json`;
        const filepath = path.join(summariesDir, filename);
        fs.writeFileSync(filepath, JSON.stringify(resultData, null, 2));
        
        // save human-readable transcript
        const transcriptFilename = `deepgram-transcript-${timestamp}.md`;
        const transcriptPath = path.join(summariesDir, transcriptFilename);
        const transcriptContent = `# deepgram nova-3 transcript\n\n**processing time:** ${resultData.processingTime}ms\n**cost:** $${resultData.cost.totalCost.toFixed(4)}\n**duration:** ${resultData.metadata.duration}s\n**channels:** ${resultData.metadata.channels}\n\n---\n\n${resultData.transcript}`;
        fs.writeFileSync(transcriptPath, transcriptContent);
        
        console.log(`💾 deepgram result saved: ${filename}, ${transcriptFilename}`);
    }
}

module.exports = SummaryGeneration;