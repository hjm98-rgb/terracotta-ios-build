import SwiftUI

/// 首页：状态条 + 两张大卡（开房 / 加房）+ 最近房间
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header

                        PixelCard {
                            HStack {
                                StatusPill(connected: model.isConnected, text: model.phaseText)
                                Spacer()
                                if let nat = model.status.natType {
                                    Text(nat)
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }

                        actionCard(
                            icon: "server.rack",
                            title: "我是房主",
                            subtitle: "在游戏里开好局域网，生成房间码发给朋友",
                            tint: Theme.accent
                        ) { model.push(.host) }

                        actionCard(
                            icon: "arrow.down.left.and.arrow.up.right",
                            title: "我是房客",
                            subtitle: "粘贴朋友给的邀请码，直接进他的世界",
                            tint: Color(hex: 0x5E8FA8)
                        ) { model.push(.join) }

                        if model.status.phase != .idle, model.status.phase != .stopped {
                            PixelCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(text: "进行中")
                                    Text(model.currentCode)
                                        .font(Theme.mono(15, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                    Text(model.status.detail)
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.textSecondary)
                                    Button {
                                        model.push(.room)
                                    } label: {
                                        Text("查看房间")
                                    }
                                    .buttonStyle(GhostButtonStyle())
                                }
                            }
                        }

                        footer
                    }
                    .padding(20)
                }
            }
            .navigationDestination(for: AppModel.Route.self) { route in
                switch route {
                case .host: HostView()
                case .join: JoinView()
                case .room: RoomView()
                case .log: LogView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("提示", isPresented: Binding(
            get: { model.alertText != nil },
            set: { if !$0 { model.alertText = nil } }
        )) {
            Button("知道了", role: .cancel) { model.alertText = nil }
        } message: {
            Text(model.alertText ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("陶瓦联机")
                    .font(Theme.mono(28, weight: .black))
                    .foregroundStyle(Theme.textPrimary)
                Text("Terracotta · iOS 独立客户端")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button {
                model.push(.log)
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.border, lineWidth: 2))
            }
        }
        .padding(.top, 8)
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(tint.opacity(0.5), lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.mono(18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textDim)
            }
            .padding(16)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 2).stroke(Theme.border, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("组网内核：EasyTier · 客户端外壳：陶瓦协议兼容")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textDim)
            Text("首次使用需在系统设置里允许「本地网络」")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.top, 12)
    }
}
