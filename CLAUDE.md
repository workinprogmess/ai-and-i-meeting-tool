# claude development guidelines - ai&i

## our collaborative approach
- **shared ownership**: this is our project - human vision + ai implementation working together
- **strategic thinking**: regularly step back to analyze big picture, code quality, and long-term direction
- **user-centered decisions**: every technical choice evaluated through impact on real user experience
- **verify before completion**: ask/confirm/verify before marking tasks or milestones complete
- **discussion before documentation**: analyze findings together before updating project state
- **quality checkpoints**: comprehensive analysis at milestone transitions

## communication style
- **lowercase preferred**: use lowercase for all documentation, git commits, and conversational exchanges
- **clear and concise**: focus on what + why in communications
- **no excessive formality**: keep language approachable and direct
- **explain decisions**: document the what/why of code/decisions/thinking/research in simple language

## git commit standards
- **format**: lowercase, what + why, no claude signatures
- **good example**: "fix cost display issue - prevents $0.00 showing during recordings"
- **bad example**: "Fix Cost Display Issue" or commits with "🤖 Generated with Claude" signatures
- **structure**: what changed + why it matters from user perspective
- **commit often**: after every significant issue resolution with clear reasoning

## documentation approach
- **lowercase headings**: use lowercase for markdown headers unless referring to proper names
- **user-focused**: explain benefits and user impact, not just technical details
- **concise insights**: provide 2-3 key educational points when explaining implementation choices
- **real examples**: use actual code snippets and scenarios from the project
- **save research**: document findings and analysis as .md files for future reference

## development priorities
1. **user experience first**: always consider impact on user workflow
2. **differentiation over commodity**: prioritize competitive advantage features before infrastructure
3. **foundation first**: ensure core functionality is solid before building advanced features
4. **reliability over features**: ensure existing functionality is rock-solid before adding new features
5. **security by design**: address electron security model, api key protection, data encryption (balanced with timeline)
6. **memory efficiency**: be mindful of resource usage, especially for long recordings
7. **clean architecture**: prefer simple, maintainable solutions over complex ones
8. **quality over speed**: build a quality product - test extensively, handle edge cases

## testing standards
- **extensive parallel testing**: user tests foundation while development focuses on differentiation
- **stress test major changes**: validate memory usage, ui synchronization, edge cases
- **document expected behaviors**: like the 10s ffmpeg startup delay
- **measure actual impact**: use real numbers for performance claims (like 99.7% memory reduction)
- **test as much as possible**: automated tests, manual validation, edge case scenarios
- **critical test scenarios**: 60+ min recordings, device switching, network failures, large transcripts
- **user experience validation**: real family scenarios, interruptions, multilingual content

## session continuity
- **update project-state.md**: keep comprehensive record of progress and decisions
- **clear status markers**: ✅ complete, 🔄 in progress, ❌ blocked, 📋 planned
- **milestone tracking**: break complex work into measurable chunks
- **version management**: semantic versioning with 0.x.x for pre-v1, reflecting milestone progress

## code quality standards (post-milestone 3.2 learnings)
- **comprehensive analysis**: regular codebase review for quality, redundancy, technical debt
- **prioritize by user impact**: address issues that affect real usage first
- **monitor don't over-engineer**: identify theoretical problems but focus on practical priorities  
- **security first**: disable nodeintegration, implement secure ipc, protect api keys, encrypt data (balanced with timeline)
- **error handling**: comprehensive error recovery, retry logic, graceful degradation
- **memory management**: proper cleanup of timers, event listeners, and resources
- **single responsibility**: avoid massive classes (renderer.js needs splitting when making major changes)
- **ipc complexity**: careful state synchronization between main and renderer processes

## strategic vision (evolved from basic transcription to human intelligence)
- **emotional journey transcripts**: @speaker references, topic emphasis, emotional context
- **human-like summaries**: sally rooney-style relationship dynamics vs corporate bullet points
- **zero data loss**: electron-audio-loopback breakthrough from ffmpeg limitations
- **single api elegance**: gemini 2.5 flash end-to-end vs complex multi-step pipelines

## risk management
- **technical risks**: memory leaks, api dependencies, device compatibility, electron security
- **user experience risks**: confusing states, data loss perception, privacy concerns  
- **recovery planning**: backup mechanisms, partial recording recovery, network failure handling
- **user tier considerations**: admin/developer vs regular user modes from project start
- **professional distribution**: testflight for beta vs manual .dmg sharing

last updated: 2025-08-31
milestone: 3.2 complete - electron-audio-loopback + recovery system, preparing for 3.3