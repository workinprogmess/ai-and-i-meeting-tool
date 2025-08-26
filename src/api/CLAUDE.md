# API Integration Guidelines - ai&i

## current architecture
### dual pipeline approach
- **Pipeline A**: Whisper (transcription) → Gemini (summary)
- **Pipeline B (planned)**: Gemini end-to-end (audio → transcript + summary)

## whisper integration best practices
### transcription standards
- **chunk size**: 5-second PCM chunks for real-time processing
- **audio format**: 16kHz, mono, 16-bit PCM for optimal accuracy
- **error handling**: retry failed chunks, log transcription costs
- **multilingual**: let whisper auto-detect language, don't force
- **accuracy target**: aim for <10% word error rate

### cost optimization
- **current cost**: ~$0.006/minute ($0.36 for 60 minutes)
- **chunking strategy**: balance real-time feedback vs API efficiency
- **failed chunk recovery**: don't lose data on single chunk failures

## gemini integration patterns
### model selection
- **always use latest**: Gemini 2.5 Flash/Pro or newest available model
- **regular model updates**: check for newer models monthly and upgrade
- **performance testing**: benchmark new models against current setup

### summary generation standards
- **input validation**: verify transcript completeness before summarization
- **prompt engineering**: research successful meeting tools' summary styles
- **context provision**: include meeting metadata (participants, duration, purpose)
- **hallucination prevention**: constrain output to source material only

### competitive research requirements
- **slack ai notes**: study their meeting summaries and action item extraction - among the best quality
- **granola**: study their summary structure and business focus
- **otter**: analyze their action item extraction
- **fireflies**: examine their conversation insights
- **amie**: review their calendar integration summaries

## gemini end-to-end pipeline (planned)
### advantages to test
- **single API call**: audio directly to Gemini 2.5 Flash/Pro
- **better context**: model sees full conversation flow for speaker diarization
- **cost efficiency**: potentially cheaper than whisper + gemini separately
- **unified processing**: consistent quality across transcript and summary

### implementation approach
- **parallel testing**: run alongside existing pipeline initially
- **quality comparison**: measure accuracy against whisper + gemini
- **cost analysis**: compare total API costs for both approaches
- **feature parity**: ensure speaker identification works as well or better

## prompt engineering standards
### human-like summary requirements
- **avoid corporate templates**: don't structure with bullet points and sections
- **conversational tone**: write like a thoughtful colleague took notes
- **business substance**: include actionable insights and decisions
- **natural language**: avoid robotic/corporate speak, keep it human

### prompt testing methodology
- **A/B comparison**: test prompts against known good summaries
- **hallucination detection**: verify all people/events mentioned are real
- **user validation**: verify that the summary accurately reflects what you remember happening in the meeting
- **iterative refinement**: improve prompts based on user feedback

## error handling requirements
### api failure scenarios
- **whisper timeout**: implement chunking for long audio files
- **gemini rate limiting**: implement exponential backoff
- **network failures**: queue requests for retry
- **partial failures**: save successful chunks, retry failed ones

### data validation
- **transcript completeness**: count expected vs actual chunks processed  
- **summary accuracy**: flag obvious hallucinations (unknown people, impossible events)
- **cost tracking**: monitor API costs and alert on anomalies
- **quality metrics**: track user satisfaction with summaries

## testing standards
### integration tests required
- **end-to-end workflow**: audio file → transcript → summary
- **real meeting validation**: test with actual 30-60 minute recordings
- **multilingual handling**: test english/hindi mixed conversations
- **interruption scenarios**: test with family/background interruptions

### performance benchmarks
- **whisper accuracy**: aim for <10% word error rate (upgraded from 15%)
- **processing speed**: real-time transcription latency <10 seconds per chunk
- **summary generation**: complete within 2 minutes for 60-minute meetings
- **cost efficiency**: stay under $0.50 per 60-minute meeting total cost

## competitive intelligence
### features to research and potentially implement
- **slack ai notes**: seamless meeting summaries with excellent action item extraction
- **granola**: seamless background recording, intelligent noise filtering
- **otter**: live collaboration, shared note-taking during meetings
- **fireflies**: conversation analytics, talk time ratios
- **amie**: calendar integration, automatic scheduling of follow-ups

### differentiation opportunities
- **human-like summaries**: natural, conversational meeting notes that avoid corporate speak
- **multilingual families**: better handling of code-switching conversations
- **developer-friendly**: open source, self-hosted option for privacy
- **emotional intelligence**: capture meeting dynamics and energy levels