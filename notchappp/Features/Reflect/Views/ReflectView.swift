import SwiftUI

/// The Reflect tab: a featured affirmation card on the left, every affirmation on the right.
struct ReflectView: View {
    @Environment(NotchViewModel.self) private var notch
    @FocusState private var focusedField: Field?

    enum Field {
        case newAffirmation
        case gratitude
    }

    var body: some View {
        HStack(spacing: 12) {
            AffirmationCard()
                .frame(width: 370)
                .staggeredAppear(0)

            VStack(spacing: 8) {
                AffirmationList(focusedField: $focusedField)
                GratitudeLine(focusedField: $focusedField)
            }
            .staggeredAppear(1)
        }
        // Keep the notch open while typing, even if the mouse wanders off.
        .onChange(of: focusedField) { _, field in notch.isEditingText = field != nil }
        .onDisappear { notch.isEditingText = false }
    }
}

/// Each affirmation gets its own deep color, picked from its text so it stays the same.
private func cardTint(for text: String) -> Color {
    let hues: [Double] = [0.58, 0.68, 0.76, 0.86, 0.95, 0.04, 0.09, 0.47, 0.52]
    let seed = text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: hues[seed % hues.count], saturation: 0.65, brightness: 0.55)
}

private struct AffirmationCard: View {
    @Environment(ReflectStore.self) private var reflect

    var body: some View {
        let current = reflect.current
        let tint = current.map { cardTint(for: $0.text) } ?? Color(white: 0.25)

        ZStack(alignment: .topLeading) {
            // Deep color fading to black, with a soft light in the corner.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.35), .black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 160, height: 160)
                        .blur(radius: 40)
                        .offset(x: -40, y: -60)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)

            // Decorative only: it must never catch clicks meant for the tab bar above.
            Text("\u{201C}")
                .font(.system(size: 90, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 10, y: -18)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let current {
                        Text(current.text)
                            .font(.system(size: 21, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .id(current.id)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your words go here.")
                                .font(.system(size: 21, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            Text("Write an affirmation on the right and it shows up big, a new one each day.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .transition(.blurFade.combined(with: .offset(y: 8)))
                Spacer(minLength: 0)

                if reflect.affirmations.count > 0 {
                    HStack(spacing: 2) {
                        Text("\(reflect.currentPosition) of \(reflect.affirmations.count)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .contentTransition(.numericText())
                        Spacer()
                        if reflect.affirmations.count > 1 {
                            NotchIconButton(symbol: "chevron.left", size: 10, tint: .white.opacity(0.8)) { change(reflect.previous) }
                            NotchIconButton(symbol: "shuffle", size: 10, tint: .white.opacity(0.8)) { change(reflect.shuffle) }
                                .help("Surprise me")
                            NotchIconButton(symbol: "chevron.right", size: 10, tint: .white.opacity(0.8)) { change(reflect.next) }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.5), value: current?.id)
    }

    private func change(_ action: () -> Void) {
        withAnimation(.smooth(duration: 0.5)) { action() }
    }
}

private struct AffirmationList: View {
    @Environment(ReflectStore.self) private var reflect
    var focusedField: FocusState<ReflectView.Field?>.Binding
    @State private var draft = ""
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Write an affirmation, press Return", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .focused(focusedField, equals: .newAffirmation)
                    .onSubmit {
                        withAnimation(.smooth(duration: 0.4)) { reflect.add(draft) }
                        draft = ""
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))

            if !reflect.affirmations.isEmpty {
                HStack {
                    Text(reflect.affirmations.count == 1 ? "1 affirmation" : "\(reflect.affirmations.count) affirmations")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    deleteAllButton
                }
                .padding(.horizontal, 4)
            }

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(reflect.affirmations) { affirmation in
                            AffirmationRow(affirmation: affirmation, isCurrent: affirmation.id == reflect.current?.id)
                                .id(affirmation.id)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
                .onAppear { if let id = reflect.current?.id { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: reflect.current?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    /// Two clicks: the first asks, the second deletes. Backs out after 3 seconds.
    private var deleteAllButton: some View {
        Button {
            if isConfirmingDeleteAll {
                withAnimation(.smooth(duration: 0.3)) { reflect.deleteAll() }
                isConfirmingDeleteAll = false
            } else {
                withAnimation(.smooth(duration: 0.2)) { isConfirmingDeleteAll = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.smooth(duration: 0.2)) { isConfirmingDeleteAll = false }
                }
            }
        } label: {
            Text(isConfirmingDeleteAll ? "Click again to delete all" : "Delete all")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(isConfirmingDeleteAll ? .white : .red.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(isConfirmingDeleteAll ? Color.red : .clear))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct AffirmationRow: View {
    let affirmation: Affirmation
    let isCurrent: Bool

    @Environment(ReflectStore.self) private var reflect
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCurrent ? cardTint(for: affirmation.text) : .white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(affirmation.text)
                .font(.system(size: 11.5, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.65))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                withAnimation(.smooth(duration: 0.3)) { reflect.delete(affirmation) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PressableButtonStyle())
            .opacity(isHovered ? 1 : 0)
            .help("Delete")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isCurrent ? 0.12 : (isHovered ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.5)) { reflect.select(affirmation) }
        }
        .onHover { hovering in withAnimation(.smooth(duration: 0.12)) { isHovered = hovering } }
        .contextMenu {
            Button("Delete", role: .destructive) { reflect.delete(affirmation) }
        }
    }
}

private struct GratitudeLine: View {
    @Environment(ReflectStore.self) private var reflect
    var focusedField: FocusState<ReflectView.Field?>.Binding
    @State private var text = ""

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundStyle(.pink)
            TextField("Today I'm grateful for…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused(focusedField, equals: .gratitude)
                .onSubmit { focusedField.wrappedValue = nil }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.pink.opacity(0.1)))
        .onAppear { text = reflect.todaysGratitude }
        .onChange(of: text) { _, newValue in
            if newValue != reflect.todaysGratitude { reflect.setTodaysGratitude(newValue) }
        }
    }
}
