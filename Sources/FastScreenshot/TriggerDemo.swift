import SwiftUI

struct TriggerDemo: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var live = LiveInput.shared
    @StateObject private var look = DesktopLook()

    private static let loop = 4.0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            let demoPressed = (0.6..<2.6).contains(t)
            ScreenStage(t: t, target: preferences.target, look: look)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    KeycapRow(inputs: live.recording ?? preferences.trigger?.inputs ?? [], pressed: { id in
                        live.recording != nil ? live.pressed.contains(id) : demoPressed
                    })
                    .offset(y: 26)
                }
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in look.reload() }
    }
}

final class DesktopLook: ObservableObject {
    @Published private(set) var wallpaper: NSImage?
    @Published private(set) var graphite = false
    private var loadedURL: URL?

    init() { reload() }

    func reload() {
        graphite = UserDefaults.standard.integer(forKey: "AppleAquaColorVariant") == 6
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen), url != loadedURL else { return }
        loadedURL = url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.thumbnail(of: url, maxPixel: 1200)
            DispatchQueue.main.async { self?.wallpaper = image }
        }
    }

    private static func thumbnail(of url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct KeycapRow: View {
    let inputs: [Input]
    let pressed: (InputID) -> Bool

    var body: some View {
        HStack(spacing: 8) {
            if inputs.isEmpty {
                Keycap(input: nil, pressed: false)
            }
            ForEach(Array(inputs.enumerated()), id: \.offset) { index, input in
                if index > 0 {
                    Text("+")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
                Keycap(input: input, pressed: pressed(input.id))
            }
        }
    }
}

struct Keycap: View {
    let input: Input?
    let pressed: Bool

    var body: some View {
        let depth: CGFloat = pressed ? 1 : 4
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 10)
                .fill(pressed ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.18)))
                .offset(y: 4 - depth)
            label
                .foregroundStyle(pressed ? Color.white : Color.primary)
                .offset(y: 4 - depth)
        }
        .frame(width: width, height: 48)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    @ViewBuilder
    private var label: some View {
        switch input {
        case .mouseButton(let button)?:
            VStack(spacing: 1) {
                Image(systemName: "computermouse").font(.system(size: 15))
                Text([0: "Left", 1: "Right", 2: "Middle"][button] ?? "Button \(button)").font(.system(size: 10, weight: .semibold))
            }
        case let input?:
            Text(input.label)
                .font(.system(size: input.label.count > 3 ? 13 : 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 6)
        case nil:
            Text("?").font(.system(size: 17, weight: .semibold, design: .rounded))
        }
    }

    private var width: CGFloat {
        guard let input, !input.isMouse else { return 58 }
        return max(52, CGFloat(input.label.count) * 9 + 24)
    }
}

private struct ScreenStage: View {
    let t: Double
    let target: CaptureTarget
    @ObservedObject var look: DesktopLook

    private let start = CGPoint(x: 0.30, y: 0.20)
    private let finish = CGPoint(x: 0.80, y: 0.66)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let progress = ease(clamp((t - 0.8) / 1.6))
            let corner = CGPoint(x: start.x + (finish.x - start.x) * progress, y: start.y + (finish.y - start.y) * progress)
            let selecting = (0.6..<2.6).contains(t)
            let rect = CGRect(
                x: start.x * size.width, y: start.y * size.height,
                width: (corner.x - start.x) * size.width, height: (corner.y - start.y) * size.height
            )
            let cursor = t < 0.8 || t > 3.6 ? start : corner

            ZStack(alignment: .topLeading) {
                wallpaper(size)

                FinderWindow(active: false, graphite: look.graphite)
                    .frame(width: size.width * 0.56, height: size.height * 0.56)
                    .offset(x: size.width * 0.07, y: size.height * 0.09)
                NotesWindow(active: true, graphite: look.graphite)
                    .frame(width: size.width * 0.44, height: size.height * 0.50)
                    .offset(x: size.width * 0.49, y: size.height * 0.30)

                if selecting, rect.width > 1 {
                    Color.black.opacity(0.28)
                        .mask(
                            Rectangle()
                                .overlay(alignment: .topLeading) {
                                    Rectangle().frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY).blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        )
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1)
                    .position(x: cursor.x * size.width, y: cursor.y * size.height)
                    .opacity(t > 3.6 ? 0 : 1)

                Color.white.opacity(flashOpacity)

                thumbnail(size)
                    .frame(width: size.width * 0.2, height: size.width * 0.13)
                    .position(x: size.width * 0.87, y: size.height * 0.16)
                    .opacity(thumbnailOpacity)
                    .offset(x: thumbnailOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.2)))
        }
    }

    @ViewBuilder
    private func wallpaper(_ size: CGSize) -> some View {
        if let image = look.wallpaper {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height).clipped()
        } else {
            LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.45), Color(red: 0.45, green: 0.3, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func thumbnail(_ size: CGSize) -> some View {
        VStack(spacing: 3) {
            GeometryReader { card in
                ZStack(alignment: .topLeading) {
                    wallpaper(card.size)
                    NotesWindow(active: true, graphite: look.graphite)
                        .frame(width: size.width * 0.44, height: size.height * 0.50)
                        .scaleEffect(card.size.width / (size.width * 0.5), anchor: .topLeading)
                        .offset(x: card.size.width * 0.12, y: card.size.height * 0.1)
                }
                .frame(width: card.size.width, height: card.size.height)
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.6)))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            Text(target == .clipboard ? "Copied" : "Saved")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 1)
        }
    }

    private var flashOpacity: Double {
        guard (2.6..<2.9).contains(t) else { return 0 }
        return 0.6 * (1 - (t - 2.6) / 0.3)
    }

    private var thumbnailOpacity: Double {
        if t < 2.75 || t > 3.9 { return 0 }
        return min(1, (t - 2.75) / 0.15) * min(1, (3.9 - t) / 0.2)
    }

    private var thumbnailOffset: CGFloat {
        t < 2.9 ? CGFloat((2.9 - t) / 0.15) * 20 : 0
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

private struct TrafficLights: View {
    let active: Bool
    let graphite: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(colors.indices, id: \.self) { index in
                Circle().fill(colors[index]).frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
            }
        }
    }

    private var colors: [Color] {
        if !active || graphite { return Array(repeating: Color.gray.opacity(active ? 0.75 : 0.45), count: 3) }
        return [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)]
    }
}

private struct WindowFrame<Content: View>: View {
    let active: Bool
    let content: Content

    init(active: Bool, @ViewBuilder content: () -> Content) {
        self.active = active
        self.content = content()
    }

    var body: some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(active ? 0.45 : 0.25), radius: active ? 10 : 5, y: active ? 5 : 2)
    }
}

private struct FinderWindow: View {
    let active: Bool
    let graphite: Bool

    private static let places: [(String, String)] = [
        ("Desktop", "menubar.dock.rectangle"), ("Documents", "doc"), ("Downloads", "arrow.down.circle"),
        ("Applications", "square.grid.2x2"), ("Pictures", "photo"),
    ]
    private static let folders = ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies"]

    var body: some View {
        WindowFrame(active: active) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    TrafficLights(active: active, graphite: graphite).padding(.bottom, 6)
                    Text("Favorites").font(.system(size: 6, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(Self.places, id: \.0) { name, symbol in
                        HStack(spacing: 3) {
                            Image(systemName: symbol).font(.system(size: 6)).foregroundStyle(Color.accentColor)
                            Text(name).font(.system(size: 6.5))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(width: 66, alignment: .leading)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.7))

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSUserName()).font(.system(size: 8, weight: .semibold))
                        .frame(height: 12)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 6) {
                        ForEach(Self.folders, id: \.self) { name in
                            VStack(spacing: 1) {
                                Image(nsImage: Self.icon(name)).resizable().frame(width: 22, height: 22)
                                Text(name).font(.system(size: 6)).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private static func icon(_ folder: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder).path)
    }
}

private struct NotesWindow: View {
    let active: Bool
    let graphite: Bool

    var body: some View {
        WindowFrame(active: active) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    TrafficLights(active: active, graphite: graphite)
                    Spacer()
                    Image(systemName: "square.and.pencil").font(.system(size: 7)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .frame(height: 18)
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly plan").font(.system(size: 9, weight: .bold))
                    Text("Monday, 10:00").font(.system(size: 6)).foregroundStyle(.secondary)
                    ForEach(["Review the release notes", "Send the slides to the team", "Book the meeting room"], id: \.self) { line in
                        HStack(spacing: 3) {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 0.8).frame(width: 6, height: 6)
                            Text(line).font(.system(size: 6.5))
                        }
                    }
                }
                .padding(8)
                Spacer(minLength: 0)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
