import SwiftUI
import Combine

struct LabThinkingBubble: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(LinearGradient(gradient: Gradient(colors: [.orange, .red]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .padding(.bottom, 2)
            }.frame(height: 38)
            
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.blue.opacity(index == dotCount ? 1.0 : 0.2))
                        .frame(width: 6, height: 6)
                        .scaleEffect(index == dotCount ? 1.2 : 1.0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.5)) { dotCount = (dotCount + 1) % 3 }
            }
            
            Spacer(minLength: 40)
        }
        .padding(.vertical, 5)
        .transition(.opacity)
    }
}
