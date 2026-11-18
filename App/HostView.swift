import SwiftUI

/// 房主页：填 MC 局域网端口 → 生成房间码 → 复制
struct HostView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scanned: [Int] = []
    @State private var isScanning = false
    @State private var copied = false
    @FocusState private var portFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    PixelCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("先在游戏里开局域网")
                                .font(Theme.mono(15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("进存档 → ESC → 「对局域网开放」→ 聊天框会给出 Local game hosted on port xxxxx")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PixelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MC 局域网端口")
                                .font(Theme.mono(12, weight: .bold))
                                .foregroundStyle(Theme.textDim)

                            TextField("例如 51234", text: $model.mcPort)
                                .keyboardType(.numberPad)
                                .focused($portFocused)
                                .font(Theme.mono(22, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardRaised)
                                .contentShape(Rectangle())
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 2))
                                .onTapGesture { portFocused = true }

                            Button {
                                portFocused = false
                                Task { await scanLocalPorts() }
                            } label: {
                                Text(isScanning ? "扫描中…" : "自动扫描本机端口")
                            }
                            .buttonStyle(GhostButtonStyle())
                            .disabled(isScanning)

                            if !scanned.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(scanned, id: \.self) { port in
                                            Button {
                                                model.mcPort = "\(port)"
                                                portFocused = false
                                            } label: {
                                                Text("\(port)")
                                                    .font(Theme.mono(14, weight: .bold))
                                                    .foregroundStyle(Theme.accent)
                                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                                    .background(Theme.accent.opacity(0.12))
                                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PixelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("房间码")
                                .font(Theme.mono(12, weight: .bold))
                                .foregroundStyle(Theme.textDim)

                            Text(model.hostCode.isEmpty ? "点下面按钮生成" : model.hostCode)
                                .font(Theme.mono(16, weight: .bold))
                                .foregroundStyle(model.hostCode.isEmpty ? Theme.textDim : Theme.accent)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                Button("重新生成") { model.regenerateCode() }
                                    .buttonStyle(GhostButtonStyle())
                                Button(copied ? "已复制 ✓" : "复制房间码") {
                                    if model.hostCode.isEmpty { model.regenerateCode() }
                                    model.copy(model.hostCode)
                                    copied = true
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        copied = false
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }

                    Button {
                        portFocused = false
                        Task { await model.startHost() }
                    } label: {
                        Text(model.isBusy ? "正在启动…" : "开始联机")
                    }
                    .buttonStyle(PixelButtonStyle())
                    .disabled(model.isBusy)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("开房")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model.hostCode.isEmpty { model.regenerateCode() }
        }
    }

    private func scanLocalPorts() async {
        isScanning = true
        defer { isScanning = false }

        let candidates = Array(25560...25580) + Array(51200...51260) + [25565]
        var found: [Int] = []

        await withTaskGroup(of: Int?.self) { group in
            for port in candidates {
                group.addTask { IPv4Socket.canConnect(port: port) ? port : nil }
            }
            for await result in group {
                if let result { found.append(result) }
            }
        }
        scanned = found.sorted()
    }
}
