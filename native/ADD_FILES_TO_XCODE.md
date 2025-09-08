# add these files to xcode project

## steps to add screencapturekit files:

1. open `AI-and-I.xcodeproj` in xcode
2. right-click on the `AI-and-I` folder in the navigator
3. select "add files to AI-and-I..."
4. add these files:
   - `ScreenCaptureManager.swift`
   - `AppPickerView.swift`
5. ensure "copy items if needed" is unchecked (files already in place)
6. ensure "add to targets: AI-and-I" is checked
7. click "add"

## then build and test:
1. build with ⌘+b
2. run with ⌘+r
3. test the new system audio capture feature

## what you'll see:
- new "select app to capture" button
- app picker sheet with meeting apps
- mixed audio recording (mic + system)

## testing checklist:
- [ ] app picker shows available apps
- [ ] can select zoom/teams/browser
- [ ] screen recording permission prompt appears
- [ ] mixed audio captures both mic and system
- [ ] no feedback loops or echo