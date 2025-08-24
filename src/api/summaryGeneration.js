const OpenAI = require('openai');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const fs = require('fs');
const path = require('path');

class SummaryGeneration {
    constructor() {
        this.openai = new OpenAI({
            apiKey: process.env.OPENAI_API_KEY
        });
        
        this.gemini = new GoogleGenerativeAI(process.env.GOOGLE_AI_KEY);
        this.geminiModel = this.gemini.getGenerativeModel({ model: 'gemini-1.5-pro' });
        
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
}

module.exports = SummaryGeneration;