import SwiftUI
import ZeroTabCore

struct SwitcherView: View {
    @ObservedObject var model: Presentation

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
                if model.isGrid {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.iconSize + 24), spacing: 0), count: model.columns), spacing: 0) {
                        appItems
                    }
                } else { HStack(spacing: 0) { appItems } }
            }
            .scrollIndicators(.hidden)
            .padding(16)
            .onChange(of: model.index) { _, value in
                guard model.items.indices.contains(value) else { return }
                proxy.scrollTo(model.items[value].id, anchor: .center)
            }
        }
    }

    private var appItems: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            VStack(spacing: 6) {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .scaledToFit().frame(width: model.iconSize, height: model.iconSize)
                    .padding(6)
                    .background {
                        if index == model.index {
                            RoundedRectangle(cornerRadius: 16).fill(.primary.opacity(0.16))
                        }
                    }
                Text(item.title).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .opacity(index == model.index ? 1 : 0)
                    .frame(width: model.iconSize + 20, height: 18)
            }
            .frame(width: model.iconSize + 24, height: model.iconSize + 48)
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
                            .id(item.id)
                            .accessibilityAddTraits(index == model.index ? [.isSelected] : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.index) { _, value in
                    guard model.items.indices.contains(value) else { return }
                    proxy.scrollTo(model.items[value].id, anchor: .center)
                }
            }
            Text("松开 Option 切换 · Esc 取消").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        }.padding(16)
    }
}
