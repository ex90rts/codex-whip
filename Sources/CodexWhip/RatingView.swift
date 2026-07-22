import SwiftUI

private enum PromptCardStyle {
    static let surface = Color(nsColor: .windowBackgroundColor).opacity(0.96)
}

struct WelcomeView: View {
    let onDetect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 17) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Codex Whip 已经启动")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("应用会直接读取 Codex 的窗口位置，不采集桌面画面，也不需要屏幕录制权限。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                Button(action: onDetect) {
                    Label("检测宠物并显示评价按钮", systemImage: "scope")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.22, green: 0.18, blue: 0.16))

                Text("依次尝试辅助功能、WindowServer 和 Electron 保存位置")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("以后可从菜单栏的魔杖图标重新打开")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PromptCardStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        )
        .padding(8)
    }
}

struct RatingView: View {
    let onPraise: () -> Void
    let onWhip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            emojiButton("👍", accessibilityLabel: "太棒了", action: onPraise)
            emojiButton("👎", accessibilityLabel: "真差劲", action: onWhip)
        }
    }

    private func emojiButton(
        _ emoji: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 23))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct LocatingPetView: View {
    var body: some View {
        HStack(spacing: 11) {
            ProgressView().controlSize(.small)
            Text("正在读取桌面上的宠物位置…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(PromptCardStyle.surface))
        .padding(6)
    }
}

struct PetNotFoundView: View {
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("没有找到 Codex 宠物", systemImage: "eye.slash")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Text("请先在 Codex 中用 /pet 唤醒宠物并保持可见。应用只读取窗口元数据，不会申请屏幕录制权限。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("重新检测", action: onRetry)
                Spacer()
                Button("关闭", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PromptCardStyle.surface)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25)))
        .padding(8)
    }
}
