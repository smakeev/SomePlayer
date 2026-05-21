import SomePlayer
import SwiftUI

struct PlayerDemoView: View {
    @ObservedObject var model: PlayerDemoViewModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    transport
                    silenceModes
                    tuningControls
                    streamDetails
                }
                .padding(proxy.size.width < 700 ? 18 : 28)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.playerText)
            }
            .background(Color.playerBackground.ignoresSafeArea())
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            artwork
            VStack(alignment: .leading, spacing: 7) {
                Text(model.title)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(Color.playerText)
                Text(metadataSubtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.playerMuted)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusPill(text: model.statusText, isActive: model.isPlaying)
                    StatusPill(text: "download \(model.downloadProgressText)", isActive: false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataSubtitle: String {
        let album = model.album.isEmpty ? nil : model.album
        return [model.artist, album].compactMap { $0 }.joined(separator: " - ")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.linearGradient(colors: [.playerInk, .playerAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let artwork = model.artwork {
                platformImage(artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var transport: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 68, height: 68)
                        .foregroundStyle(.white)
                        .background(model.canPlay ? Color.playerInk : Color.gray.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canPlay)

                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(model.sliderValue) },
                            set: {
                                print("[SomePlayerDebug][UI] slider value changed value=\($0)")
                                model.updateSeekingValue(Float($0))
                            }
                        ),
                        in: 0...Double(max(model.timeline.sliderMaximumValue, 1)),
                        onEditingChanged: { editing in
                            print("[SomePlayerDebug][UI] slider editing=\(editing) slider=\(model.sliderValue) max=\(model.timeline.sliderMaximumValue) canSeek=\(model.canSeek)")
                            editing ? model.beginSeeking() : model.commitSeek()
                        }
                    )
                    .disabled(!model.canSeek)

                    HStack {
                        Text(model.currentTimeText)
                        Spacer()
                        Text(model.durationText)
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.playerMuted)
                }

                Button(action: model.reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(Color.playerPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var silenceModes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Silence handling")
                .font(.headline)
            HStack(spacing: 10) {
                ModeButton(
                    title: "Smart Speed",
                    isSelected: model.selectedMode == .smart
                ) {
                    model.toggleMode(.smart)
                }
                ModeButton(
                    title: "Speed Up Silence",
                    isSelected: model.selectedMode == .speedUp
                ) {
                    model.toggleMode(.speedUp)
                }
                ModeButton(
                    title: "Adaptive Speed",
                    isSelected: model.selectedMode == .adaptiveSpeed
                ) {
                    model.toggleMode(.adaptiveSpeed)
                }
            }
        }
    }

    private var tuningControls: some View {
        VStack(spacing: 18) {
            ControlRow(
                title: "Base rate",
                value: String(format: "%.1fx", model.baseRate),
                range: 0.5...2.0,
                binding: $model.baseRate,
                reset: model.resetRate
            )
            ControlRow(
                title: "Pitch",
                value: "\(Int(model.pitch)) cents",
                range: -1200...1200,
                binding: $model.pitch,
                reset: model.resetPitch
            )
            Toggle(isOn: $model.voiceBoost) {
                Label("Voice boost", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .toggleStyle(.switch)
        }
        .padding(18)
        .background(Color.playerPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var streamDetails: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            DetailTile(title: "Applied rate", value: String(format: "%.2fx", model.appliedRate))
            DetailTile(title: "Saved", value: model.savedSecondsText)
            DetailTile(title: "Sample rate", value: model.sampleRateText)
            DetailTile(title: "Range requests", value: model.rangeHeaderText)
            DetailTile(title: "Current task", value: model.statusText)
            DetailTile(title: "URL", value: model.streamURL.host() ?? "remote")
        }
    }

    private func platformImage(_ image: SomePlayerImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}

private struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(.horizontal, 8)
                .foregroundStyle(isSelected ? Color.white : Color.playerText)
                .background(isSelected ? Color.playerInk : Color.playerTile, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ControlRow: View {
    let title: String
    let value: String
    let range: ClosedRange<Float>
    @Binding var binding: Float
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.playerMuted)
                Button(action: reset) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
            }
            Slider(
                value: Binding(
                    get: { Double(binding) },
                    set: { binding = Float($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
        }
    }
}

private struct DetailTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.playerMuted)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.playerText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.playerTile, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.playerAccent.opacity(0.2) : Color.playerTile, in: Capsule())
            .foregroundStyle(isActive ? Color.playerAccentBright : Color.playerMuted)
    }
}

private extension Color {
    static let playerBackground = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let playerPanel = Color(red: 0.13, green: 0.16, blue: 0.18)
    static let playerTile = Color(red: 0.19, green: 0.23, blue: 0.26)
    static let playerInk = Color(red: 0.10, green: 0.33, blue: 0.39)
    static let playerAccent = Color(red: 0.12, green: 0.62, blue: 0.66)
    static let playerAccentBright = Color(red: 0.41, green: 0.90, blue: 0.90)
    static let playerText = Color(red: 0.94, green: 0.96, blue: 0.95)
    static let playerMuted = Color(red: 0.66, green: 0.73, blue: 0.74)
}
