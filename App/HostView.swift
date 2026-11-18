import SwiftUI

/// 房主页：填 MC 局域网端口 → 生成房间码 → 复制/分享
struct HostView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scanned: [Int] = []
    @State private var isScanning = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    stepHeader("1", "先在游戏里开局域网")
                    PixelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("进存档 → ESC → 「对局域网开放」")
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.textSecondary)
                            Text("聊天框会弹出 Local game hosted on port xxxxx，把这个端口填到下面。")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    stepHeader("2", "填端口")
                    PixelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                TextField("25565", text: $model.mcPort)
                                    .keyboardType(.numberPad)
                                    .font(Theme.mono(18, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(12)
                                    .background(Theme.cardRaised)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.border, lineWidth: 2))

                                Button {
                                    Task { await scanLocalPorts() }
                                } label: {
                                    Text(isScanning ? "扫描中" : "自动扫描")
                                        .font(Theme.mono(13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 12)
                                        .background(Theme.cardRaised)
                                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.border, lineWidth: 2))
                                }
                                .disabled(isScanning)
                            }

                            if !scanned.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(scanned, id: \.self) { port in
                                            Button("\(port)") { model.mcPort = "\(port)" }
                                                .font(Theme.mono(13, weight: .bold))
                                                .foregroundStyle(Theme.accent)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Theme.accent.opacity(0.12))
                                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    stepHeader("3", "把房间码发给朋友")
                    PixelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(model.hostCode.isEmpty ? "点下面的按钮生成" : model.hostCode)
                                .font(Theme.mono(16, weight: .bold))
                                .foregroundStyle(model.hostCode.isEmpty ? Theme.textDim : Theme.accent)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)

                            HStack(spacing: 10) {
                                Button("生成新的") { model.regenerateCode() }
                                    .buttonStyle(GhostButtonStyle())
                                Button("复制") {
                                    if model.hostCode.isEmpty { model.regenerateCode() }
                                    model.copy(model.hostCode)
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }

                    Button {
                        Task { await model.startHost() }
                    } label: {
                        Text(model.isBusy ? "正在启动…" : "开始联机")
                    }
                    .buttonStyle(PixelButtonStyle())
                    .disabled(model.isBusy)

                    Text("同一时间只能有一个网络扩展在跑；开了别的加速器会把它顶掉。")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(20)
            }
        }
        .navigationTitle("开房")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model.hostCode.isEmpty { model.regenerateCode() }
        }
    }

    private func stepHeader(_ index: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(index)
                .font(Theme.mono(12, weight: .black))
                .foregroundStyle(Color(hex: 0x1A120C))
                .frame(width: 22, height: 22)
                .background(Theme.accent)
            Text(text)
                .font(Theme.mono(14, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// 扫本机正在监听的端口，帮用户把 MC 的局域网端口找出来。
    /// 只探常见范围内、且本机能连上的 loopback 端口，避免无意义扫描。
    private func scanLocalPorts() async {
        isScanning = true
        defer { isScanning = false }

        let candidates = Array(25560...25575) + Array(51200...51260) + [25565, 19132]
        var found: [Int] = []

        await withTaskGroup(of: Int?.self) { group in
            for port in candidates {
                group.addTask { Self.canConnect(port: port) ? port : nil }
            }
            for await result in group {
                if let result { found.append(result) }
            }
        }
        scanned = found.sorted()
    }

    private static func canConnect(port: Int) -> Bool {
        guard let address = IPv4Socket.loopback(port: port) else { return false }
        return IPv4Socket.canConnect(address, timeout: 0.25)
    }
}
