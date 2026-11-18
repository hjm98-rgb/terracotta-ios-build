import SwiftUI

/// 房间页：显示 IP:端口、进度、成员、断开
struct RoomView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    PixelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                StatusPill(connected: model.isConnected, text: model.phaseText)
                                Spacer()
                                Text(model.currentRole == .host ? "房主" : "房客")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(model.status.detail)
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let error = model.status.errorText {
                                Text(error)
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if model.currentRole == .guest {
                        PixelCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("游戏里填这个地址（IP:端口）")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundStyle(Theme.textDim)

                                Text(model.connectAddressText)
                                    .font(Theme.mono(24, weight: .black))
                                    .foregroundStyle(Theme.success)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("多人游戏 → 直接连接 → 粘贴。冒号用英文半角。")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button(copied ? "已复制 ✓" : "复制 \(model.connectAddressText)") {
                                    model.copy(model.connectAddressText)
                                    copied = true
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        copied = false
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    } else {
                        PixelCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("把房间码发给朋友")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundStyle(Theme.textDim)
                                Text(model.currentCode)
                                    .font(Theme.mono(18, weight: .black))
                                    .foregroundStyle(Theme.accent)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(copied ? "已复制 ✓" : "复制房间码") {
                                    model.copy(model.currentCode)
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

                    progressCard

                    if !model.status.logs.isEmpty {
                        PixelCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("最近事件")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundStyle(Theme.textDim)
                                ForEach(Array(model.status.logs.suffix(5).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.textDim)
                                        .lineLimit(2)
                                }
                                Button("查看完整日志") { model.push(.log) }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }

                    Button {
                        Task {
                            await model.stop()
                            model.pop()
                        }
                    } label: {
                        Text("断开")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.danger))
                }
                .padding(20)
            }
        }
        .navigationTitle("房间")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressCard: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("连接进度")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                ForEach(steps, id: \.id) { step in
                    HStack(spacing: 10) {
                        Image(systemName: step.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(step.done ? Theme.success : Theme.textDim)
                        Text(step.title)
                            .font(Theme.mono(13))
                            .foregroundStyle(step.done ? Theme.textPrimary : Theme.textDim)
                        Spacer()
                        if step.active && !step.done {
                            ProgressView().controlSize(.mini).tint(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private struct Step {
        let id: Int
        let title: String
        var done: Bool
        var active: Bool
    }

    private var steps: [Step] {
        let phase = model.status.phase
        let order: [ProviderStatus.Phase] = [.starting, .negotiating, .discoveringPeer, .forwarding, .ready]
        let currentIndex = order.firstIndex(of: phase) ?? -1
        let titles = ["启动组网核心", "P2P 打洞 / 接入中转", "发现房主", "建立端口通道", "就绪"]
        return titles.enumerated().map { index, title in
            Step(id: index, title: title, done: currentIndex >= index, active: currentIndex == index)
        }
    }
}
