import SwiftUI

/// 房客页：粘贴邀请码 → 连接
struct JoinView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    private var parsed: InviteCode? { InviteCode.parse(model.guestCodeInput) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    PixelCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("粘贴朋友给的邀请码")
                                .font(Theme.mono(15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("格式 U/XXXX-XXXX-XXXX-XXXX，带空格或多余文字也能识别。")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PixelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("U/XXXX-XXXX-XXXX-XXXX", text: $model.guestCodeInput)
                                .font(Theme.mono(17, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .textContentType(.oneTimeCode)
                                .focused($focused)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardRaised)
                                .contentShape(Rectangle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(borderColor, lineWidth: 2)
                                )
                                .onTapGesture { focused = true }

                            HStack(spacing: 8) {
                                Image(systemName: parsed == nil ? "exclamationmark.triangle" : "checkmark.seal")
                                    .foregroundStyle(parsed == nil ? Theme.textDim : Theme.success)
                                Text(parsed == nil ? "等待有效邀请码" : "校验通过 · \(parsed!.networkName)")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(parsed == nil ? Theme.textDim : Theme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }

                    Button {
                        focused = false
                        Task { await model.startGuest() }
                    } label: {
                        Text(model.isBusy ? "正在连接…" : "连接房间")
                    }
                    .buttonStyle(PixelButtonStyle())
                    .disabled(model.isBusy || parsed == nil)

                    Text("公共节点在境外，国内直连可能偏慢。")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("加入")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var borderColor: Color {
        if model.guestCodeInput.isEmpty { return Theme.border }
        return parsed == nil ? Theme.danger.opacity(0.6) : Theme.success.opacity(0.6)
    }
}
