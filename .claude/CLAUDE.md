# ai&i meeting tool development guidelines

## core principles
- **incremental progress over big bangs**: small changes that compile and test
- **thorough validation before claiming completion**: never mark done without evidence
- **systematic testing**: test each component individually before integration  
- **git discipline**: commit logical chunks, never massive changes
- **ask before finishing**: always confirm completion with user

## before coding checklist
- **BP-1 (MUST)**: ask clarifying questions about requirements
- **BP-2 (MUST)**: draft approach and get user confirmation for complex work
- **BP-3 (MUST)**: identify similar code patterns in existing codebase
- **BP-4 (MUST)**: plan test strategy before writing code

## implementation standards
### explanation and communication requirements
- **EC-1 (CRITICAL)**: explain every step we take and why it's the right approach
- **EC-2**: provide context for each change - what problem it solves and how
- **EC-3**: when making technical decisions, explain trade-offs and alternatives considered
- **EC-4**: always show the "why" behind the code, not just the "what"

### competitive research requirements
- **CR-1**: research how established apps (granola, otter, fireflies, amie) handle similar features
- **CR-2**: identify best practices from successful meeting tools before implementing
- **CR-3**: understand user expectations from existing tools in the market
- **CR-4**: document competitive insights in comments when implementing similar features

### user experience design
- **UX-1**: design clear user journeys for each milestone before coding
- **UX-2**: map out complete user flow to identify obvious gaps early
- **UX-3**: consider edge cases from user perspective (what if recording fails mid-meeting?)
- **UX-4**: validate UX assumptions with user before building complex features

### code quality assurance for non-technical founder
- **CQ-1**: provide regular confidence updates on code quality and testing coverage
- **CQ-2**: explain performance implications and optimizations being implemented
- **CQ-3**: highlight edge cases being handled and defensive programming measures
- **CQ-4**: demonstrate thorough testing with specific examples and test results
- **CQ-5**: point out best practices being followed and industry standards met
- **CQ-6**: leave clear comments explaining complex logic for future maintenance

### error handling requirements
- **EH-1**: every api call must have try/catch with specific error messages
- **EH-2**: user-facing errors must be actionable ("check internet connection" vs "error 500")
- **EH-3**: critical data (audio, transcripts) must have backup/recovery mechanisms
- **EH-4**: long operations must show progress indicators

### testing requirements  
- **T-1**: unit tests for all core functions (transcription, summarization, audio processing)
- **T-2**: integration tests for full workflows (record → transcribe → summarize)
- **T-3**: edge case testing (long meetings, poor audio, api failures)
- **T-4**: data persistence validation (can we recover if app crashes?)

### git workflow
- **G-1**: commit after each logical feature completion, not at milestone end
- **G-2**: commit messages must explain "what" and "why", not just "what"  
- **G-3**: never commit broken code (must compile and basic functionality work)
- **G-4**: include test results in commit messages when relevant

## quality gates - never skip these
### definition of done checklist
- [ ] feature works as specified
- [ ] error cases handled gracefully  
- [ ] user can recover from failures
- [ ] tests written and passing
- [ ] code follows project patterns
- [ ] commit message explains changes
- [ ] user has verified functionality
- [ ] competitive research completed where relevant
- [ ] user journey validated
- [ ] code quality explanation provided

## critical reminders for ai&i project
- **audio data is precious**: 50-minute meetings cannot be lost due to poor error handling
- **real-time operations need progress feedback**: users must see what's happening
- **api calls can fail**: whisper, claude, all external services need fallbacks
- **large data operations need chunking**: don't process 600 chunks all at once
- **never claim "transcript recovered" without user verification**: show evidence
- **explain every technical decision**: founder needs to understand what we're building and why
- **research competition continuously**: users expect ai&i to work as well as granola/otter

## project-specific lessons learned
### transcript recovery incident (2025-08-25)
- **ISSUE**: claimed "complete transcript recovered" when only ~100/600 chunks captured
- **ROOT CAUSE**: manual extraction process, overconfidence, no systematic validation
- **PREVENTION**: always count/measure data completeness before claiming success
- **LESSON**: show user the numbers (X chunks out of Y total) not just "success"

### audio recording failure incident (2025-08-25)  
- **ISSUE**: 50-minute meeting audio file lost due to missing save functionality
- **ROOT CAUSE**: AudioCapture class designed for streaming only, no file persistence
- **PREVENTION**: test file saving with short recordings before long meetings
- **LESSON**: critical data paths must be tested end-to-end, not just individually

### summary hallucination incident (2025-08-25)
- **ISSUE**: gemini generated fictional meeting participants and events
- **ROOT CAUSE**: insufficient context, poor prompt design, incomplete transcript
- **PREVENTION**: validate summaries against source material, provide specific context
- **LESSON**: ai summarization needs constraints and fact-checking mechanisms

## communication templates
### when explaining code changes:
"I'm implementing [FEATURE] because [PROBLEM IT SOLVES]. The approach I'm using is [TECHNICAL APPROACH] which is considered best practice because [INDUSTRY STANDARD/RESEARCH]. This follows the pattern used by [COMPETITIVE APP] and handles [EDGE CASES] gracefully."

### when providing quality assurance:
"The code we just wrote follows [BEST PRACTICES], includes [SPECIFIC TESTS], handles [EDGE CASES], and performs well because [PERFORMANCE MEASURES]. This gives us confidence because [EVIDENCE]."