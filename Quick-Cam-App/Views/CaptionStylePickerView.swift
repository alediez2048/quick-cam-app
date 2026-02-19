import SwiftUI
import AppKit

struct CaptionStylePickerView: View {
    @Binding var selectedStyle: CaptionStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1 — Style Presets
            Text("STYLE")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(CaptionStyle.allPresets, id: \.styleName) { preset in
                    presetButton(for: preset)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)

            // Section 2 — Customization
            Text("CUSTOMIZE")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(spacing: 0) {
                // Position
                HStack {
                    Text("Position")
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $selectedStyle.position) {
                        ForEach(CaptionPosition.allCases) { pos in
                            Text(pos.displayName).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.1))

                // Font
                HStack {
                    Text("Font")
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $selectedStyle.fontName) {
                        ForEach(CaptionFont.allFonts) { font in
                            Text(font.displayName)
                                .font(.custom(font.postScriptName, size: 13))
                                .tag(font.postScriptName)
                        }
                    }
                    .frame(width: 180)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.1))

                // Font Size
                HStack {
                    Text("Size")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(selectedStyle.fontSize))pt")
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                Slider(value: $selectedStyle.fontSize, in: 48...120, step: 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                Divider().background(Color.white.opacity(0.1))

                // Text Color
                HStack {
                    Text("Text color")
                        .foregroundColor(.white)
                    Spacer()
                    ColorPicker("", selection: textColorBinding)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.1))

                // Highlight Color
                HStack {
                    Text("Highlight color")
                        .foregroundColor(.white)
                    Spacer()
                    ColorPicker("", selection: highlightColorBinding)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.1))

                // Background Color
                HStack {
                    Text("Background color")
                        .foregroundColor(.white)
                    Spacer()
                    ColorPicker("", selection: backgroundColorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.1))

                // Outline
                HStack {
                    Text("Outline")
                        .foregroundColor(.white)
                    Spacer()
                    Text(selectedStyle.strokeWidth > 0 ? "\(Int(selectedStyle.strokeWidth))" : "Off")
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                HStack(spacing: 8) {
                    Slider(value: $selectedStyle.strokeWidth, in: 0...8, step: 1)
                    if selectedStyle.strokeWidth > 0 {
                        ColorPicker("", selection: strokeColorBinding)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                Divider().background(Color.white.opacity(0.1))

                // Highlighter
                HStack {
                    Text("Highlighter")
                        .foregroundColor(.white)
                    Spacer()
                    ColorPicker("", selection: textHighlighterColorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    // MARK: - Preset Button

    private func presetButton(for preset: CaptionStyle) -> some View {
        let isSelected = selectedStyle.styleName == preset.styleName
        return Button {
            selectedStyle = preset
        } label: {
            VStack(spacing: 4) {
                // Mini preview swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: preset.backgroundColor == .clear ? .darkGray : preset.backgroundColor))
                        .frame(height: 36)

                    Text("Aa")
                        .font(.custom(preset.fontName, size: 14).bold())
                        .foregroundColor(Color(nsColor: preset.textColor))
                        .shadow(color: preset.strokeWidth > 0 ? Color(nsColor: preset.strokeColor).opacity(0.8) : .clear, radius: 1, x: 1, y: 1)
                }

                Text(preset.styleName)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Bindings (NSColor <-> SwiftUI Color)

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedStyle.textColor) },
            set: { selectedStyle.textColor = NSColor($0) }
        )
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedStyle.highlightColor) },
            set: { selectedStyle.highlightColor = NSColor($0) }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedStyle.backgroundColor) },
            set: { selectedStyle.backgroundColor = NSColor($0) }
        )
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedStyle.strokeColor) },
            set: { selectedStyle.strokeColor = NSColor($0) }
        )
    }

    private var textHighlighterColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedStyle.textHighlighterColor) },
            set: { selectedStyle.textHighlighterColor = NSColor($0) }
        )
    }
}
