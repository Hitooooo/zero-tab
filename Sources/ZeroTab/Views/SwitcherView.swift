import SwiftUI
import ZeroTabCore

struct SwitcherView: View {
    @ObservedObject var model: Presentation
    let onSelect: (String) -> Void
    let onHover: (String) -> Void

    var body: some View {
        Group {
            if model.mode == .applications { applications }
            else { windows }
        }
        .frame(width: model.width, height: model.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.mode == .applications ? "应用切换器" : "窗口切换器")
    }

    private var applications: some View {
        ScrollViewReader { proxy in
            ScrollView(model.isGrid ? .vertical : .horizontal) {
                Group {
                    if model.isGrid {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.cellWidth), spacing: ApplicationLayout.iconGap), count: model.columns), spacing: ApplicationLayout.rowSpacing) {
                            appItems
                        }
                    } else { HStack(spacing: ApplicationLayout.iconGap) { appItems } }
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

    private var appItems: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            Button { onSelect(item.id) } label: {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .scaledToFit().frame(width: model.iconSize, height: model.iconSize)
                    .background {
                        if index == model.index {
                            SelectionOutline().transition(.identity)
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
            .accessibilityAddTraits(index == model.index ? [.isSelected] : [])
        }
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.appName).font(.headline)
                Spacer()
                Text("\(model.items.count) 个窗口").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            Button { onSelect(item.id) } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                                    Text(item.title).font(.system(size: 14, weight: index == model.index ? .medium : .regular))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    if item.window?.minimized == true {
                                        Image(systemName: "minus.rectangle").help("已最小化")
                                    }
                                    if item.location == .other {
                                        Label(item.window?.spaceLabel ?? "其他桌面", systemImage: "arrow.up.right").font(.caption)
                                    } else if item.location == .unknown {
                                        Text("位置未确认").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12).frame(height: 52)
                                .background {
                                    if index == model.index { RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.13)) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onContinuousHover { phase in if case .active = phase { onHover(item.id) } }
                            .id(item.id)
                            .accessibilityAddTraits(index == model.index ? [.isSelected] : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.index) { _, value in
                    guard model.shouldScrollSelection, model.items.indices.contains(value) else { return }
                    proxy.scrollTo(model.items[value].id, anchor: .center)
                }
            }
            Text("点击或松开 Option 切换 · Esc 取消").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        }.padding(16)
    }
}

/// The caption can be clicked without making it participate in row layout.
private struct ApplicationHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width,
                    height: rect.height + ApplicationLayout.nameHeight - ApplicationLayout.captionOverlap))
    }
}
