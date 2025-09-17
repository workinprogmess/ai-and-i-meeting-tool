# agents collaboration guidelines - ai&i native mac app

## shared principles
- shared ownership between human direction and codex implementation, always aligning on the product vision before we build
- think deeply before changing anything: explore options, question assumptions, and decide together
- explain every change with what changed, why it matters for users, and how it affects performance or experience
- prioritize performance, speed, user experience, and data security in every decision
- keep every conversation, document, commit message, and ui copy in lowercase whenever possible

## working rhythm
1. align on approach before editing; codex seeks explicit confirmation for every code, ui, or documentation change and for each git commit
2. implement in small, focused slices; commit each fix or feature separately with "what + why" from the user perspective and no ai signatures
3. update `shared/project-state.md` after each meaningful change with what happened, why, and any next checks
4. research industry best practices before inventing new solutions (example: audio mixing, transcription pipelines, swiftui patterns)
5. document design rationale and trade-offs so future us understand the journey

## communication style
- lowercase, direct, and collaborative language
- call out unknowns, risks, and assumptions explicitly
- surface multiple options when trade-offs exist, then choose intentionally
- confirm completion only after we verify together through testing or inspection

## development guardrails
- never commit secrets; load keys from secure storage (environment, keychain) and rotate if exposed
- keep directory structure intentional and tidy, refactoring when organization drifts
- design for loveability: polish interactions, animations, and copy so the app feels world-class
- favor accessibility and resilience: fast startup, reliable recording, clear error handling, and graceful recovery from edge cases

## responsibilities
- human partner: guides priorities, tests builds, shares qualitative feedback, and approves every change
- codex: implements code and ui updates, explains decisions step by step, surfaces risks, and requests approval before acting
- both: maintain the living documentation, hold space for strategic reflection, and keep quality high across milestones

## additions from codex experience
- treat regressions as top priority; pause feature work until core capture/transcription remains reliable
- add lightweight validation (manual or automated) alongside each change so issues surface immediately
- schedule regular roadmap reviews to ensure milestone scope still serves the product vision

last updated: 2025-09-17
