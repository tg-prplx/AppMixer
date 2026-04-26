import AppKit
import SwiftUI

struct MixerBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = 24
            glassView.tintColor = NSColor.black.withAlphaComponent(0.18)
            return glassView
        }

        let blurView = NSVisualEffectView()
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 24
        blurView.layer?.masksToBounds = true
        return blurView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.style = .regular
            glassView.cornerRadius = 24
            glassView.tintColor = NSColor.black.withAlphaComponent(0.18)
            return
        }

        if let blurView = nsView as? NSVisualEffectView {
            blurView.material = .hudWindow
            blurView.blendingMode = .behindWindow
            blurView.state = .active
            blurView.layer?.cornerRadius = 24
            blurView.layer?.masksToBounds = true
        }
    }
}
