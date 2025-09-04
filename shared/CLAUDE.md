# claude development guidelines - ai&i native mac app

## our collaborative approach
- **shared ownership**: this is our project - human vision + ai implementation working together
- **think before building**: brainstorm deeply, explore options, understand the problem completely before jumping to implementation
- **explain everything**: document every decision, even small changes - what changed and why it matters
- **strategic thinking**: regularly step back to analyze the big picture and long-term implications
- **user-centered decisions**: every technical choice evaluated through real user impact
- **verify before completion**: ask/confirm/verify before marking tasks or milestones complete

## communication style
- **lowercase preferred**: use lowercase for all documentation, git commits, and conversational exchanges
- **deep exploration**: when facing decisions, explore multiple approaches and discuss trade-offs thoroughly
- **clear explanations**: explain the reasoning behind every implementation choice
- **no excessive formality**: keep language approachable and direct
- **question assumptions**: challenge ideas to ensure we're building the right thing

## git commit standards
- **format**: lowercase, what + why, no claude signatures
- **example**: "add core audio mixed capture - enables hardware-level audio mixing"
- **structure**: what changed + why it matters from user perspective
- **commit frequency**: after every meaningful change with clear reasoning

## native development philosophy

### apple's excellence standards
- **follow human interface guidelines**: native patterns, consistent behavior, intuitive interactions
- **world-class ux**: minimal, elegant, feels effortless to use
- **magical performance**: so fast it feels instant - app startup, recording start, ui responsiveness
- **native integration**: proper macos behavior, permissions, system integration

### critical learnings from our journey
- **work with the platform, not against it**: leverage native capabilities instead of fighting limitations
- **research industry standards first**: understand how professionals actually solve problems before implementing
- **foundation quality matters**: build the right architecture from the start for long-term success
- **user experience drives technical decisions**: choose solutions that create the best user experience

## project management approach

### milestone structure
- **clear milestones**: each milestone represents working, testable functionality
- **granular todos**: break down milestones into specific, actionable tasks
- **comprehensive testing**: write test cases for each milestone, execute them thoroughly
- **milestone completion**: only mark complete after all test cases pass
- **semantic versioning**: 0.1.0 (milestone 1), 0.2.0 (milestone 2), etc.
- **branch workflow**: merge to main branch only after milestone completion
- **git releases**: create release tag with each milestone completion

### documentation discipline
- **update project-state.md**: document every decision, progress, and learning
- **commit everything**: every small change gets committed with explanation
- **track progress**: use todos within milestones to maintain momentum
- **preserve decisions**: document why we chose specific approaches

### development rhythm
1. **plan thoroughly**: understand requirements and approach before coding
2. **implement incrementally**: build working pieces that can be tested immediately  
3. **test continuously**: validate functionality and user experience at each step
4. **write test cases**: comprehensive testing for each milestone
5. **execute tests**: ensure all functionality works as expected
6. **document decisions**: capture what we learned and why we chose specific solutions
7. **merge and release**: milestone completion → main branch → git release

this foundation ensures we build a professional-grade native mac app while maintaining our proven collaborative approach and learning-driven development process.

last updated: 2025-09-04  
focus: native mac app excellence through strategic thinking and incremental progress