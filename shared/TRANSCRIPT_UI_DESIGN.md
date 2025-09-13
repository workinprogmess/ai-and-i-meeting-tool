# transcript ui/ux design system

## design philosophy
minimal, warm, paper-like interface inspired by japanese aesthetics.
focus on clarity and calm. no visual noise, just thoughtful simplicity.

## visual design

### typography
- **font**: san francisco (system font - free on macos)
- **sizes**:
  - title: 20pt bold (editable recording name from transcript)
  - metadata: 12pt medium (date, duration, speakers)
  - speaker label: 16pt medium
  - transcript text: 16pt regular
  - timestamp: 12pt regular
  - buttons: 14pt medium
- **all lowercase** throughout ui (transcript content stays as spoken)

### color palette (japanese-inspired)
```
background:     #fbfaf5 (kinari-iro - natural/dough)
surface:        #fffffc (gofun-iro - chalk white)
primary text:   #2c2c2c (sumi - charcoal)
secondary:      #6b6b6b (hai-iro - ash grey)
tertiary:       #9d9d9d (disabled state)

speaker labels: #e7e7eb (all speakers same color for now)

actions:
primary button: #eae5e3 (background) + #6b6b6b (text)
secondary:      #f3f3f3 (background) + #6b6b6b (text)
success:        #e8f5e8 (pale green background)
warning:        #fff4e6 (pale amber background)
error:          #ffe8e8 (pale red background)

selection:      #eae5e3 (highlight color)
hover:          #f5f0ee (subtle warmth)
```

### spacing & layout
```
margins:       24px (window edges)
padding:       16px (cards)
gap-large:     24px (between sections)
gap-medium:    16px (between elements)
gap-small:     8px (within elements)
line-height:   1.6 (transcript text)
```

### animations
- **duration**: 200ms
- **easing**: ease-in-out
- **types**:
  - fade in for new content
  - slide down for expanding sections
  - subtle scale (0.98) for button press
  - wave animation for recording

## wireframes

### 7.1 main landing page (meetings list)
```
┌─────────────────────────────────────────────────────┐
│  ai & i                              [search] ⚙     │
├─────────────────────────────────────────────────────┤
│                                                     │
│     ┌───────────────────────────────────────┐      │
│     │   start a new meeting                 │      │
│     └───────────────────────────────────────┘      │
│                                                     │
│  today                                              │
│  ─────                                             │
│  ○ team standup                           45 min   │
│  ○ 1:1 with sarah                        23 min   │
│                                                     │
│  yesterday                                          │
│  ─────────                                         │
│  ○ design review                          67 min   │
│  ○ product planning                       34 min   │
│                                                     │
│  december 11                                        │
│  ────────────                                      │
│  ○ all hands                              52 min   │
│  ○ customer call                          38 min   │
│                                                     │
│  [load more...]                                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 7.2 recording in progress
```
┌─────────────────────────────────────────────────────┐
│  ai & i                                   ← back   │
├─────────────────────────────────────────────────────┤
│                                                     │
│                                                     │
│              recording in progress                  │
│                                                     │
│                    12:34                           │
│                                                     │
│               ∿∿∿  ∿∿∿  ∿∿∿                       │
│              (audio wave animation)                │
│                                                     │
│                                                     │
│          ┌─────────────────────────┐               │
│          │    end meeting          │               │
│          └─────────────────────────┘               │
│                                                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 7.3 end meeting confirmation
```
┌──────────────────────────────────┐
│                                  │
│  end meeting?                    │
│                                  │
│  are you sure you want to end    │
│  this recording?                 │
│                                  │
│  [cancel]         [end meeting]  │
│                                  │
└──────────────────────────────────┘
```

### 7.4 transcription in progress
```
┌─────────────────────────────────────────────────────┐
│  ai & i                                   ← back   │
├─────────────────────────────────────────────────────┤
│                                                     │
│              transcribing audio...                 │
│                                                     │
│              ○○○○○○○○○○                            │
│              (progress indicator)                  │
│                                                     │
│              duration: 45:23                       │
│                                                     │
│              this will take a moment               │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 7.6 transcript view (admin mode with tabs)
```
┌─────────────────────────────────────────────────────┐
│  ← back              ai & i              [admin]   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  team standup discussion                    [edit] │
│  dec 13, 2024 • 45 min • 3 speakers               │
│                                                     │
│  [gemini] [deepgram] [assembly]                    │
│  ─────────────────────────────────                 │
│  quality: 95% • cost: $0.09 • time: 3.2s          │
│                                                     │
│  @alex  00:23                                      │
│  so the main issue we're seeing is with the        │
│  authentication flow. users can't sign in          │
│  after the recent update.                          │
│                                                     │
│  @jordan  01:45                                    │
│  yeah, i noticed that too. when users try         │
│  to sign in with google, it just spins            │
│  forever. checked the logs?                        │
│                                                     │
│  @alex  02:10                                      │
│  exactly. logs show a 403 from the oauth          │
│  endpoint. we need to fix that before             │
│  shipping tomorrow.                                │
│                                                     │
│                           ┌────────────────┐       │
│                           │ 🔗 📋 📤 ✂️    │       │
│                           └────────────────┘       │
│                          (floating actions)        │
└─────────────────────────────────────────────────────┘
```

### 7.7 speaker segments (no boxes - clean open design)
```
@alex  00:23
so the main issue we're seeing is with the
authentication flow. users can't sign in
after the recent update.

@jordan  01:45
yeah, i noticed that too. when users try
to sign in with google, it just spins
forever. checked the logs?
```

### 7.9 export options (mac style popover)
```
        ┌─────────────────────┐
        │ export as           │
        ├─────────────────────┤
        │ plain text (.txt)   │
        │ markdown (.md)      │
        │ pdf document        │
        │ word (.docx)        │
        └─────────────────────┘
                ▼
         [export icon]
```

### 7.5 quit confirmation
```
┌──────────────────────────────────┐
│                                  │
│  recording in progress           │
│                                  │
│  quitting will stop the current  │
│  recording. are you sure?        │
│                                  │
│  [keep recording]    [quit]      │
│                                  │
└──────────────────────────────────┘
```

## interaction patterns

### navigation flow
1. **landing page** → view all meetings
2. **start meeting** → recording view
3. **end meeting** → confirmation → processing → transcript
4. **click meeting** → transcript view
5. **floating actions** → share/export/corrections

### hover states
- meeting items: background #f5f0ee
- buttons: opacity 0.9
- floating actions: scale 1.05

### selection
- text selection: standard mac behavior
- highlight color: #eae5e3
- multi-select: cmd+click

### keyboard shortcuts
- `cmd+n`: new meeting
- `cmd+f`: find in transcript
- `cmd+e`: corrections mode
- `cmd+k`: copy link
- `cmd+shift+c`: copy transcript
- `cmd+shift+e`: export
- `space`: play/pause audio
- `esc`: back/cancel

## responsive behavior

### window sizes
- **minimum**: 700x500px
- **default**: 1000x700px
- **full screen**: supported

### content adaptation
- transcript width: max 800px centered
- maintain 60-80 character line length
- responsive text wrapping

## implementation notes

### swiftui structure
```swift
// main app
NavigationStack {
    MeetingsListView()  // landing page
        .navigationDestination(for: Meeting.self) { meeting in
            TranscriptView(meeting: meeting)
        }
}

// floating action tray
HStack(spacing: 12) {
    ActionButton(icon: "link", action: copyLink)
    ActionButton(icon: "doc.on.doc", action: copyText)
    ActionButton(icon: "square.and.arrow.up", action: export)
    ActionButton(icon: "scissors", action: corrections)
}
.padding(12)
.background(Color(hex: "fffffc"))
.cornerRadius(20)
.shadow(radius: 4, y: 2)
```

### animations
```swift
// wave animation for recording
Wave()
    .stroke(lineWidth: 2)
    .animation(.easeInOut(duration: 1.5).repeatForever())
```

## missing considerations

### audio playback
- mini player at bottom of transcript
- sync highlight with audio position
- speed controls (1x, 1.5x, 2x)

### search
- cmd+f for in-transcript search
- global search from landing page
- highlight matches

### data persistence
- auto-save edits
- offline access to transcripts
- icloud sync (future)

## next steps

1. implement landing page with meetings list
2. create recording flow with animations
3. build transcript view with tabs
4. add floating action tray
5. implement corrections ui (phase 4)
6. optimize performance (phase 5)