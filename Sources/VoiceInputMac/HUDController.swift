import AppKit
import Combine

/// Compact AppKit status pill. Frame-based layout only — SwiftUI hosting in a
/// borderless panel crashes on macOS when the view size keeps changing.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var dot: NSView?
    private var label: NSTextField?
    private var meterFill: NSView?
    private var cancellables: Set<AnyCancellable> = []
    private let state: AppState
    private var lastStatus = ""
    private var lastPhase: AppState.Phase = .idle
    private var lastPolishing = false
    private var polishHideWork: DispatchWorkItem?
    private var visible = false

    private let panelSize = NSSize(width: 188, height: 34)
    private let meterMaxWidth: CGFloat = 52

    init(state: AppState) {
        self.state = state
    }

    func start() {
        state.$phase
            .combineLatest(state.$statusLine, state.$level, state.$isPolishing)
            .throttle(for: .milliseconds(80), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _, _, _, _ in
                self?.render()
            }
            .store(in: &cancellables)
        render()
    }

    private var shouldShow: Bool {
        state.isArmed || state.isPolishing || polishHideWork != nil
    }

    private func render() {
        if !state.isPolishing && lastPolishing {
            schedulePolishHide()
        }
        if !shouldShow {
            if visible {
                panel?.orderOut(nil)
                visible = false
            }
            return
        }
        if panel == nil {
            buildPanel()
        }
        applyContent()
        if !visible {
            position()
            panel?.orderFrontRegardless()
            visible = true
        }
    }

    private func schedulePolishHide() {
        polishHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.polishHideWork = nil
            self.render()
        }
        polishHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = panelSize.height / 2
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let dot = NSView(frame: NSRect(x: 12, y: 13, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 26, y: 8, width: 100, height: 18)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false
        label.isSelectable = false
        label.refusesFirstResponder = true

        let meterTrack = NSView(frame: NSRect(x: 128, y: 14, width: meterMaxWidth, height: 6))
        meterTrack.wantsLayer = true
        meterTrack.layer?.cornerRadius = 3
        meterTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let meterFill = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: 6))
        meterFill.wantsLayer = true
        meterFill.layer?.cornerRadius = 3
        meterTrack.addSubview(meterFill)

        effect.addSubview(dot)
        effect.addSubview(label)
        effect.addSubview(meterTrack)
        panel.contentView = effect

        self.panel = panel
        self.dot = dot
        self.label = label
        self.meterFill = meterFill
    }

    private func applyContent() {
        let isPolishing = state.isPolishing
        let color: NSColor = isPolishing ? .systemPurple : color(for: state.phase)
        if isPolishing != lastPolishing || (!isPolishing && state.phase != lastPhase) {
            dot?.layer?.backgroundColor = color.cgColor
            meterFill?.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
            lastPolishing = isPolishing
            lastPhase = state.phase
        }
        if state.statusLine != lastStatus {
            label?.stringValue = state.statusLine
            lastStatus = state.statusLine
        }
        let width = isPolishing
            ? 4
            : 4 + CGFloat(min(max(state.level, 0), 0.2)) / 0.2 * (meterMaxWidth - 4)
        meterFill?.frame.size.width = width
        meterFill?.isHidden = isPolishing
    }

    private func color(for phase: AppState.Phase) -> NSColor {
        switch phase {
        case .capturing: return .systemRed
        case .transcribing: return .systemOrange
        case .listening, .preparing: return .systemGreen
        default: return .systemGray
        }
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panelSize.width / 2
        let y = visible.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: false)
    }
}
