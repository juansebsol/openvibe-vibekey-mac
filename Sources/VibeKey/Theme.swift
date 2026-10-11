import SwiftUI

/// Dark palette modeled on Ulanzi Studio, with a teal accent.
enum Theme {
    static let teal = Color(red: 0.14, green: 0.85, blue: 0.79)
    /// Deeper teal that still reads on the light device body.
    static let tealOnLight = Color(red: 0.0, green: 0.68, blue: 0.63)
    static let onTeal = Color(red: 0.02, green: 0.17, blue: 0.16)
    static let canvas = Color(red: 0.112, green: 0.116, blue: 0.132)
    static let panel = Color(red: 0.094, green: 0.098, blue: 0.112)
    static let sidebar = Color(red: 0.137, green: 0.141, blue: 0.158)
    static let field = Color(red: 0.068, green: 0.072, blue: 0.084)
    static let hairline = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.10)
    static let text = Color(white: 0.94)
    static let secondary = Color(white: 0.63)
    static let tertiary = Color(white: 0.43)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.32)
    static let red = Color(red: 1.0, green: 0.43, blue: 0.41)
}

struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Buttons

/// Square icon button with hover highlight (header, trash, etc.).
struct IconButtonStyle: ButtonStyle {
    var active = false
    var destructive = false
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, active: active, destructive: destructive, size: size)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let active: Bool
        let destructive: Bool
        let size: CGFloat
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(active ? Theme.teal : hover ? (destructive ? Theme.red : Theme.text) : Theme.text.opacity(0.78))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.13 : (hover || active) ? 0.07 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration) }

    private struct StyleBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onTeal)
                .padding(.horizontal, 16)
                .frame(minWidth: 84, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.teal.opacity(configuration.isPressed ? 0.78 : 1)))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration) }

    private struct StyleBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : hover ? 0.10 : 0.07)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

/// Text-only button in an accent color.
struct LinkButtonStyle: ButtonStyle {
    var tint: Color = Theme.teal
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration, tint: tint) }

    private struct StyleBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint.opacity(configuration.isPressed ? 0.7 : 1))
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(hover ? 0.12 : 0)))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

// MARK: - Fields

struct FieldBackground: ViewModifier {
    var focused = false
    var invalid = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(invalid ? Theme.red.opacity(0.7) : focused ? Theme.teal.opacity(0.75) : Theme.stroke, lineWidth: 1)
            )
    }
}

struct VKTextField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.tertiary))
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
            .foregroundStyle(Theme.text)
            .focused($focused)
            .modifier(FieldBackground(focused: focused, invalid: invalid))
    }
}

struct VKTextEditor: View {
    @Binding var text: String
    var height: CGFloat = 64
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.vertical, 6)
            .frame(height: height)
            .modifier(FieldBackground(focused: focused))
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .gridColumnAlignment(.trailing)
    }
}

/// Field-styled label used as the face of a Menu.
struct MenuFieldLabel: View {
    var icon: String?
    var text: String
    var placeholder = false
    var width: CGFloat = 240

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 16)
            }
            Text(text)
                .foregroundStyle(placeholder ? Theme.tertiary : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        }
        .font(.system(size: 13))
        .frame(width: width - 20, alignment: .leading)
        .modifier(FieldBackground())
        .contentShape(Rectangle())
    }
}

/// A Menu that looks like one of our fields and shows a checkmark next to the current choice.
struct ChoiceMenu<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    var title: (T) -> String
    var icon: ((T) -> String)? = nil
    var width: CGFloat = 240

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    if let icon {
                        Label(title(option), systemImage: icon(option)).tag(option)
                    } else {
                        Text(title(option)).tag(option)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuFieldLabel(icon: icon?(selection), text: title(selection), width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Segmented pills

struct PillSegments<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    var title: (T) -> String
    var icon: ((T) -> String)? = nil
    var dot: ((T) -> Bool)? = nil
    var stretch = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(text: title(option), icon: icon?(option), dot: dot?(option) ?? false,
                        selected: option == selection, stretch: stretch) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
    }

    private struct Segment: View {
        let text: String
        let icon: String?
        let dot: Bool
        let selected: Bool
        let stretch: Bool
        let action: () -> Void
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).font(.system(size: 11.5, weight: .medium)) }
                    Text(text)
                    if dot {
                        Circle().fill(Theme.teal).frame(width: 5, height: 5)
                    }
                }
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.text : hover ? Theme.text.opacity(0.85) : Theme.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: stretch ? .infinity : nil)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.12) : hover ? Color.white.opacity(0.04) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.white.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

// MARK: - Key caps

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
    }
}
