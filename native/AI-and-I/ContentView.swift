import SwiftUI

struct ContentView: View {
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 20) {
            // App title
            Text("AI & I")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Native Mac Meeting Intelligence")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Recording status
            if isRecording {
                VStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                    
                    Text("Recording...")
                        .font(.title2)
                        .fontWeight(.medium)
                }
            } else {
                Image(systemName: "mic.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Control button
            Button(action: toggleRecording) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            // TODO: Start audio recording with Core Audio
            print("Starting recording...")
        } else {
            // TODO: Stop recording and process
            print("Stopping recording...")
        }
    }
}

#Preview {
    ContentView()
}