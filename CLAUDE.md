# claude development guidelines - ai&i

## communication style
- **lowercase preferred**: use lowercase for all documentation, git commits, and conversational exchanges
- **clear and concise**: focus on what + why in communications
- **no excessive formality**: keep language approachable and direct

## git commit standards
- **format**: lowercase, what + why, no claude signatures
- **good example**: "fix cost display issue - prevents $0.00 showing during recordings"
- **bad example**: "Fix Cost Display Issue" or commits with "🤖 Generated with Claude" signatures
- **structure**: what changed + why it matters from user perspective

## documentation approach
- **lowercase headings**: use lowercase for markdown headers unless referring to proper names
- **user-focused**: explain benefits and user impact, not just technical details
- **concise insights**: provide 2-3 key educational points when explaining implementation choices
- **real examples**: use actual code snippets and scenarios from the project

## development priorities
1. **user experience first**: always consider impact on user workflow
2. **reliability over features**: ensure existing functionality is rock-solid before adding new features
3. **memory efficiency**: be mindful of resource usage, especially for long recordings
4. **clean architecture**: prefer simple, maintainable solutions over complex ones

## testing standards
- **stress test major changes**: validate memory usage, ui synchronization, edge cases
- **document expected behaviors**: like the 10s ffmpeg startup delay
- **measure actual impact**: use real numbers for performance claims (like 99.7% memory reduction)

## session continuity
- **update project-state.md**: keep comprehensive record of progress and decisions
- **clear status markers**: ✅ complete, 🔄 in progress, ❌ blocked, 📋 planned
- **milestone tracking**: break complex work into measurable chunks

## code style preferences
- **minimal comments**: let code be self-documenting unless complex business logic requires explanation
- **follow existing patterns**: match the codebase's established conventions
- **security first**: never expose secrets, always validate inputs, handle errors gracefully

last updated: 2025-08-28
milestone: 3.1.9 complete, preparing for 3.2 authentication & backend