import SwiftUI

/// 日志页：实时刷 NE 上报的日志
struct LogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.status.logs.isEmpty {
                            Text("暂无日志。连接一次之后这里会有内核输出。")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textDim)
                                .padding(.top, 20)
                        } else {
                            ForEach(Array(model.status.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.status.logs.count) { count in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(copied ? "已复制" : "复制全部") {
                    model.copy(model.status.logs.joined(separator: "\n"))
                    copied = true
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("失败") || lower.contains("fail") {
            return Theme.danger
        }
        if lower.contains("warn") || lower.contains("超时") {
            return Theme.warning
        }
        if lower.contains("ready") || lower.contains("成功") || lower.contains("就绪") {
            return Theme.success
        }
        return Theme.textSecondary
    }
}
