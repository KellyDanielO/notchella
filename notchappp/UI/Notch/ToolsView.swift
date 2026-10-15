import SwiftUI

/// The Tools tab: a slim switcher down the left edge, and the chosen page beside it.
/// Keeping Dev and Images under one tab keeps the header to four tabs, which is all that
/// fits beside the camera on smaller notches.
struct ToolsView: View {
    @Environment(NotchViewModel.self) private var notch

    var body: some View {
        HStack(spacing: 12) {
            ToolsRail()
            ZStack {
                switch notch.toolsPage {
                case .dev:
                    DevView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .notchPanel()
                        .transition(.blurFade.combined(with: .offset(y: -12)))
                case .images:
                    ImageToolsView()
                        .transition(.blurFade.combined(with: .offset(y: 12)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notch.toolsPage)
        }
    }
}

/// Two stacked icon buttons; the selected one sits on a white disc that slides between them.
private struct ToolsRail: View {
    @Environment(NotchViewModel.self) private var notch
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 6) {
            ForEach(NotchViewModel.ToolsPage.allCases, id: \.self) { page in
                let isSelected = notch.toolsPage == page
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(.white).matchedGeometryEffect(id: "page", in: selection)
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { notch.toolsPage = page }
                    }
                    .help(page.title)
            }
        }
        .padding(4)
        .frame(maxHeight: .infinity)
        .notchPanel(cornerRadius: 19)
    }
}
