# ai&i transcript format sample

## overview
this document demonstrates the enhanced transcript format with emotions, topics, and acoustic events for rich meeting documentation.

## format structure

### speaker identification
- `@me` - primary voice from microphone (person recording)
- `@me-2`, `@me-3` - additional voices from microphone if present
- `@speaker1`, `@speaker2`, etc - participants from system audio
- `@system` - audio from screen shares, videos, or other system sources

### metadata format
- `[emotion intensity]` - emotional state with intensity (mildly/somewhat/very/extremely)
- `[topic-tags]` - up to 3 contextual topics per segment, hyphenated
- `(acoustic events)` - sounds and audio cues in parentheses
- `[meeting events]` - technical/meeting flow events in square brackets

### emotion intensity scale
- mildly - slight emotion
- somewhat - moderate emotion  
- very - strong emotion
- extremely - intense emotion

### common acoustic events (audio-detectable)
- human sounds: `(laughs)`, `(sighs)`, `(coughs)`, `(clears throat)`
- environmental: `(door closes)`, `(typing)`, `(phone ringing)`, `(doorbell)`
- actions: `(sipping drink)`, `(papers rustling)`, `(footsteps)`
- work-from-home: `(child voice)`, `(dog barking)`, `(construction noise)`

### meeting events
- technical: `[audio cutting out]`, `[connection unstable]`, `[echo/feedback]`
- participation: `[speaker2 audio drops]`, `[multiple people talking]`, `[silence - possible mute]`
- verbal cues: `[someone says "you're muted"]`, `[someone says "can you hear me?"]`

## sample transcript

```
MEETING TRANSCRIPT
==================

@speaker1: [cheerful] [introductions] [team-meeting]
hey everyone, can you all hear me okay?

@me: [confirming] [introductions] [team-meeting]
yeah, loud and clear. jessica, i think you're muted

[someone unmuted - based on verbal cue]

@speaker2: [apologetic] [introductions] [technical-issues]
(adjusting headphones) sorry about that! ready to review the payment flow?

@me: [focused] [therapist-app] [payment-flow]
yes! so we need to solve the payout timing issue that therapists keep reporting

@speaker1: [curious] [payment-flow] [user-feedback]
(typing) how many complaints did we get last week?

@me: [somewhat concerned] [payment-flow] [user-feedback]
(sighs) about thirty. mostly about the 5-day hold on payments

@speaker2: [thoughtful] [payment-flow] [solution-proposal]
what if we switch to stripe connect? they have instant payouts

@speaker3: [very excited] [payment-flow] [technical-design]
oh that's perfect! i just implemented that for another project

[overlapping voices - animated discussion]

@me: [interested] [payment-flow] [technical-design]
tell us more about the implementation

@speaker3: [confident] [payment-flow] [technical-design]
it's actually pretty straightforward. two-step onboarding, handles all compliance

(coffee machine noise in background)

@speaker1: [mildly frustrated] [workplace-frustration] [process-concerns]
ugh, speaking of compliance... legal still hasn't approved our last vendor

@me: [empathetic] [workplace-frustration]
(laughs dryly) three weeks and counting, right?

@speaker2: [somewhat annoyed] [workplace-frustration] [process-concerns]
don't get me started. my aws upgrade request has been stuck for a month

[brief pause - collective sighing]

@speaker1: [shifting-mood] [casual-chat] [weekend-plans]
anyway... let's not go down that rabbit hole. anyone doing anything fun this weekend?

@me: [cheerful] [travel-discussion] [personal-life]
actually yeah! flying to portland to see my sister

@speaker3: [very interested] [travel-discussion] [restaurant-recommendations]
oh nice! you have to try pok pok. best wings i've ever had

@speaker2: [nostalgic] [travel-discussion] [personal-life]
i miss portland. lived there for two years before moving here

(doorbell rings)

@me: [slightly annoyed] [interruption]
(footsteps) sorry, delivery. be right back

[pause - door conversation muffled]

@speaker1: [casual] [casual-chat]
(to others) while they're gone, did you all see the game last night?

@speaker2: [excited] [sports-talk]
that last quarter was insane!

@speaker3: [disappointed] [sports-talk]
(groans) don't remind me. i had money on the other team

[laughter]

@me: [returning] [payment-flow] [refocusing]
(sitting down) back! so where were we? stripe connect?

@speaker1: [helpful] [payment-flow] [recap]
yeah, jessica was explaining the two-step onboarding

@speaker3: [focused] [payment-flow] [technical-design] [compliance]
right, so the beauty is it handles kyc automatically...

[audio cutting out - speaker3]

@speaker3: [frustrated] [technical-issues]
(robotic voice) ...can you... still... hear...

@me: [helpful] [technical-issues]
you're breaking up jessica

[speaker3 audio drops]

@speaker2: [continuing] [payment-flow] [timeline]
while she reconnects, when do we need this live?

@me: [decisive] [payment-flow] [timeline] [decision-making]
ideally by end of month. therapists are getting really frustrated

@speaker1: [concerned] [user-feedback] [business-impact]
yeah, we've had two big practices threaten to leave

[speaker3 audio returns]

@speaker3: [apologetic] [technical-issues]
sorry, wifi crashed. stupid router

@me: [understanding] [technical-issues]
no worries! we were discussing timeline

@speaker3: [confident] [payment-flow] [next-steps] [timeline]
end of month is doable. i can have a technical spec by thursday

@speaker2: [agreeable] [next-steps] [task-assignment]
i'll handle the legal review for compliance

@speaker1: [responsible] [next-steps] [task-assignment]
and i'll draft the communication for therapists

(child voice in background: "daddy, i'm hungry!")

@speaker2: [apologetic] [interruption] [work-from-home]
(muting briefly) sorry team, school just let out

@me: [understanding] [work-from-home]
no problem at all! i think we have our action items

@speaker1: [wrapping-up] [meeting-wrap-up] [action-items]
perfect. so jessica does technical spec, you handle legal, i do comms

@me: [organized] [meeting-wrap-up] [action-items]
exactly. i'll send a recap email with deadlines

@speaker3: [casual] [casual-chat] [food-discussion]
before we go, anyone want to grab lunch after the all-hands tomorrow?

@speaker2: [interested] [food-discussion] [team-bonding]
i'm down! that new ramen place?

@me: [enthusiastic] [food-discussion] [team-bonding]
yes! i've been wanting to try it

@speaker1: [friendly] [meeting-end]
cool, see you all at the all-hands then!

[multiple people saying goodbye]

@me: [friendly] [meeting-end]
thanks everyone! great meeting

[meeting ends - silence]

---
CONSISTENCY CHECK APPLIED:
- maintained "payment-flow" throughout 
- kept "therapist-app" as consistent prefix where relevant
- standardized all emotion intensities to scale
- verified speaker numbering continuity
- merged similar topics: "food-talk" and "food-discussion" → "food-discussion"
- limited to max 3 topics per segment
- preserved natural flow from work topics to personal chat

TITLE: therapist app payment flow design review
```

## key principles

1. **audio-only detection**: only mark what can be heard, not seen
2. **context matters**: use participant reactions to infer events ("you're muted")
3. **consistency**: maintain speaker labels and topic names throughout
4. **human reality**: include work-from-home interruptions naturally
5. **technical honesty**: mark audio issues and unclear segments
6. **emotion granularity**: use the 4-level intensity scale consistently
7. **topic discipline**: maximum 3 topics per segment, keep them broad initially
8. **non-judgmental transcription**: capture workplace frustrations and personal discussions factually without editorial commentary

## topics guidelines

### when to maintain topics
- keep using same topic tag while discussion continues
- even if diving into details, maintain the broad topic

### when to introduce new topics  
- conversation genuinely shifts to new subject
- someone explicitly says "moving on to..." or "different topic..."
- natural meeting transitions (intro → main discussion → wrap-up)
- organic drift to personal topics (work frustration → weekend plans)

### common topic patterns

#### work topics
- meeting flow: `[introductions]`, `[agenda-review]`, `[meeting-wrap-up]`
- project topics: `[product-name]`, `[feature-name]`, `[metric-type]`
- process topics: `[technical-design]`, `[solution-proposal]`, `[decision-making]`
- action topics: `[next-steps]`, `[task-assignment]`, `[timeline]`

#### personal/social topics
- casual: `[casual-chat]`, `[off-topic-banter]`, `[catching-up]`
- personal life: `[weekend-plans]`, `[vacation-discussion]`, `[family-talk]`
- interests: `[sports-talk]`, `[movie-discussion]`, `[hobby-chat]`
- recommendations: `[restaurant-recommendations]`, `[travel-tips]`, `[book-suggestions]`
- team social: `[team-bonding]`, `[lunch-plans]`, `[after-work-drinks]`

#### sensitive topics (transcribe factually)
- workplace: `[workplace-frustration]`, `[process-concerns]`, `[team-dynamics]`
- feedback: `[constructive-criticism]`, `[performance-discussion]`
- venting: `[workload-concerns]`, `[deadline-pressure]`

#### meta topics
- technical: `[technical-issues]`, `[audio-problems]`, `[connection-issues]`
- interruptions: `[interruption]`, `[work-from-home]`, `[background-noise]`
- meeting management: `[refocusing]`, `[time-check]`, `[parking-lot-item]`

## handling sensitive content

when conversations include venting, frustration, or criticism:
1. transcribe accurately without editorial judgment
2. use neutral emotion labels (frustrated, concerned) not extreme ones
3. use factual topic tags like `[workplace-frustration]` not `[complaining]`
4. preserve the human element - these moments matter for understanding team dynamics
5. natural conversation flow often includes: work topic → frustration → casual chat → back to work

example:
```
@speaker1: [very frustrated] [deadline-pressure] [workload-concerns]
i honestly don't know how we're supposed to ship this by friday with half the team out

@me: [empathetic] [deadline-pressure] [team-dynamics]
(sighs) yeah, it's been rough. maybe we should talk to leadership about pushing it?

@speaker2: [shifting-mood] [casual-chat]
speaking of being out... anyone else jealous of tom's hawaii pics?

@me: [amused] [vacation-discussion]
(laughs) so jealous! those beaches looked amazing
```

## post-processing

after transcription, apply consistency check:
1. merge similar topics (payment vs payments → payment)
2. verify speaker label continuity
3. standardize emotion intensities
4. flag any unclear audio segments
5. preserve sensitive content factually
6. generate title from main work topics (not personal tangents)

## implementation notes

- this format works across all transcription services (gemini, deepgram, assembly)
- ui should display emotions and topics as subtle tags/badges
- acoustic events can be slightly grayed out for less visual emphasis
- meeting events should be visually distinct (maybe italics or different color)
- consider making topics clickable for filtering/searching later
- personal/casual topics should be displayed same as work topics (no stigma)
- sensitive topics handled with same professional presentation