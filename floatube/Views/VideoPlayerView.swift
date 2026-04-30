import AppKit
import SwiftUI
import YouTubePlayerKit

struct VideoPlayerView: View {
    let player: YouTubePlayer

    var body: some View {
        YouTubePlayerView(player) { state in
            switch state {
            case .idle:
                ProgressView()
            case .ready:
                EmptyView()
            case .error:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Failed to load video")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(RightClickBlocker())
        .background(Color.black)
    }
}

private struct RightClickBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> RightClickBlockerView {
        RightClickBlockerView()
    }
    func updateNSView(_ nsView: RightClickBlockerView, context: Context) {}
}

private class RightClickBlockerView: NSView {
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp {
            return hit
        }
        return nil
    }
}
