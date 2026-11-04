import SwiftUI
import ZeroTabCore

struct SwitcherView: View {
    @ObservedObject var model: Presentation
    let onSelect: (String) -> Void
    let onHover: (String) -> Void

    var body: some View {
        iconPanel
            .frame(width: model.width, height: model.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.mode == .applications ? "应用切换器" : "窗口切换器")
    }

    private var iconPanel: some View {
        ScrollViewReader { proxy in
            ScrollView(model.isGrid ? .vertical : .horizontal) {
                Group {
                    if model.isGrid {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.cellWidth), spacing: ApplicationLayout.iconGap), count: model.columns), spacing: model.rowSpacing) {
                            iconItems
                        }
                    } else { HStack(spacing: ApplicationLayout.iconGap) { iconItems } }
                }
                .padding(ApplicationLayout.padding)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.index) { _, value in
                guard model.shouldScrollSelection, model.items.indices.contains(value) else { return }
                proxy.scrollTo(model.items[value].id, anchor: .center)
            }
        }
    }

    private var iconItems: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            Button { onSelect(item.id) } label: {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .scaledToFit().frame(width: model.iconSize, height: model.iconSize)
                    .background {
                        if index == model.index {
                            SelectionOutline().transition(.identity)
                        }
                    }
                    .overlay(alignment: .top) {
                        if let window = item.window {
                            HStack(spacing: 4) {
                                Text(window.spaceBadge ?? "?")
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if window.minimized {
                                    Image(systemName: "minus.rectangle")
                                        .font(.system(size: 10))
                                }
                            }
                                .foregroundStyle(.secondary)
                                .frame(width: model.iconSize, height: 14)
                                .offset(y: -18)
                                .help((window.spaceLabel ?? "位置未确认") + (window.minimized ? "，已最小化" : ""))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: model.cellWidth, height: model.cellHeight)
                    .overlay(alignment: .bottom) {
                        Text(item.title).font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                            .opacity(index == model.index ? 1 : 0)
                            .frame(width: model.cellWidth, height: ApplicationLayout.nameHeight)
                            .offset(y: ApplicationLayout.nameHeight - ApplicationLayout.captionOverlap)
                    }
                    .contentShape(ApplicationHitShape())
            }
            .buttonStyle(.plain)
            .onContinuousHover { phase in if case .active = phase { onHover(item.id) } }
            .id(item.id)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.window.map {
                ($0.spaceLabel ?? "位置未确认") + ($0.minimized ? "，已最小化" : "")
            } ?? "")
            .accessibilityAddTraits(index == model.index ? [.isSelected] : [])
        }
    }
}

/// The caption can be clicked without making it participate in row layout.
private struct ApplicationHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width,
                    height: rect.height + ApplicationLayout.nameHeight - ApplicationLayout.captionOverlap))
    }
}
