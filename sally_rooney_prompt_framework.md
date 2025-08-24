# sally rooney-style summary prompt framework for ai&i

## core sally rooney elements

### conversational intimacy
- warm, personal tone that feels like a friend telling you what happened
- natural speech patterns with varied sentence lengths
- emotional awareness without being dramatic

### emotional subtext
- reading between the lines of what people actually meant
- capturing unspoken tensions, enthusiasm, frustration
- understanding power dynamics and relationships

### narrative flow
- tells the story of the meeting, not just lists facts
- natural transitions between topics and moments
- creates coherence from messy, real conversations

## base prompt template

```
you are summarizing a meeting transcript in the style of sally rooney - conversational, emotionally intelligent, and intimate. 

capture not just what was said, but what was felt and meant. write like you're telling a close friend what happened, with warmth and insight into the human dynamics.

key elements to include:
- the emotional arc of the meeting
- who drove decisions and how
- moments of tension, agreement, or excitement  
- what wasn't said but was understood
- clear action items with ownership
- the overall story, not just bullet points

transcript:
{transcript}

write a summary that feels human, warm, and perceptive - like sally rooney would if she attended this meeting.
```

## gpt-5 specific prompt

```
you're creating a meeting summary in sally rooney's conversational style - intimate, emotionally intelligent, with natural rhythm.

meeting context:
- participants: {participants}
- duration: {duration} minutes
- topic: {topic}

your task: write like you're telling someone who cares about these people what really happened in this room. capture the undercurrents, the moments where someone's voice changed, the silences that meant something.

structure loosely as:
1. opening: set the scene, who was there, what the energy felt like
2. flow: the conversation's natural progression, key moments, turning points
3. dynamics: who led, who hesitated, what tensions emerged
4. resolution: decisions made, next steps, how it ended
5. action items: clear ownership and deadlines

transcript:
{transcript}

write with sally rooney's warmth and perceptiveness - make this meeting come alive.
```

## gemini 2.5 pro specific prompt

```
create a meeting summary using sally rooney's narrative voice - conversational intimacy with emotional intelligence.

you're not writing a business report. you're telling the story of what happened between these people, with all the subtlety and warmth that sally rooney brings to human interactions.

meeting details:
- participants: {participants} 
- duration: {duration} minutes
- context: {context}

focus on:
- the emotional journey of the conversation
- power structures and relationship dynamics  
- what people really meant vs what they said
- moments of connection, tension, or breakthrough
- the human story behind the business decisions

format: natural paragraphs that flow like a story, not sections or bullet points. include action items naturally within the narrative.

transcript:
{transcript}

write as if sally rooney attended this meeting and is sharing what she observed about these people and their interactions.
```

## emotional intelligence markers

### enthusiasm detection
- "sarah's voice lifted when discussing the new feature"
- "you could hear the excitement building as they talked through possibilities"
- "mark leaned forward, clearly energized by the idea"

### frustration/tension patterns  
- "there was a pause after john's suggestion - the kind that means people are thinking carefully about how to respond"
- "lisa's questions had an edge, probing deeper than usual"
- "the conversation circled back to budget three times, each round a bit more strained"

### consensus building
- "slowly, agreement began to form around sarah's approach"  
- "after some back and forth, they found their way to common ground"
- "the room settled into a shared understanding"

### power dynamics
- "john deferred to sarah's expertise, stepping back from his initial position"
- "when mike spoke, the conversation shifted - he had that effect"
- "the decision was collaborative in name, but clearly driven by lisa's vision"

## meeting type adaptations

### daily standups
focus on: team energy, blockers that create stress, momentum shifts
tone: quick, intimate check-in on how everyone's really doing

### strategy sessions
focus on: vision alignment, creative tensions, breakthrough moments  
tone: deeper exploration of ideas and the people behind them

### client meetings
focus on: relationship dynamics, unspoken client concerns, team chemistry
tone: diplomatic but perceptive about what's really happening

### retrospectives
focus on: emotional honesty, team growth, vulnerable moments
tone: reflective, supportive, growth-oriented

## quality checklist

### does the summary have:
- [ ] conversational warmth (not corporate)
- [ ] emotional insight (what people felt)
- [ ] natural flow (story vs bullet points)  
- [ ] relationship dynamics (who influenced whom)
- [ ] clear action items (woven into narrative)
- [ ] human moments (pauses, energy shifts, connections)
- [ ] sally rooney's intimate observation style

### avoid:
- robotic business language
- pure bullet point lists
- missing emotional context
- ignoring power dynamics
- dry recitation of facts
- corporate jargon without warmth

## testing framework

for each llm, test with:
1. **high-emotion meeting** (tense discussion, breakthrough moment)
2. **routine meeting** (standard planning, low drama)
3. **multi-stakeholder meeting** (complex dynamics, competing interests)

measure:
- emotional intelligence accuracy
- narrative flow quality  
- action item clarity
- sally rooney style authenticity