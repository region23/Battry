import SwiftUI
import AppKit

/// Панель "О программе" с информацией о разработчике и ссылками
struct AboutPanel: View {
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject private var i18n = Localization.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Информация о разработчике
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    Text(i18n.t("about.developer"))
                        .font(.headline)
                    Spacer()
                }
                
                // Ссылки
                VStack(alignment: .leading, spacing: 8) {
                    AboutLinkView(
                        icon: "paperplane.fill",
                        title: "Telegram",
                        subtitle: "@region23",
                        url: "https://t.me/region23"
                    )
                    
                    AboutLinkView(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: i18n.t("about.source.code"),
                        subtitle: "GitHub",
                        url: "https://github.com/region23/Battry"
                    )
                    
                    AboutLinkView(
                        icon: "arrow.down.circle.fill",
                        title: i18n.t("about.download"),
                        subtitle: i18n.t("about.latest.version"),
                        url: "https://github.com/region23/Battry/releases/latest"
                    )
                }
            }
            
            // Telegram канал - приглушенный блок
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "tv.fill")
                        .foregroundColor(.primary)
                        .font(.title3)
                    Text(i18n.t("about.channel.title"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                Text(i18n.t("about.channel.description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil)
                
                Button {
                    if let url = URL(string: "https://t.me/pavlenkodev") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .font(.callout)
                        Text("@pavlenkodev")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.primary.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.68, green: 0.81, blue: 0.91),  // Пастельный голубой
                        Color(red: 0.56, green: 0.73, blue: 0.85)   // Мягкий синий
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.4)
            )
            
            .cornerRadius(12)
            .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
            
           
            
            Spacer(minLength: 2)
            
            // Версия приложения и проверка обновлений
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Text(appVersion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    updateStatusView
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await updateChecker.checkForUpdates()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if case .checking = updateChecker.status {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            Text(i18n.t("update.check"))
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled({
                        if case .checking = updateChecker.status {
                            return true
                        }
                        return false
                    }())
                    Spacer()
                }
                
                Text(i18n.t("about.copyright"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        }
        .padding(12)
        .frame(minHeight: 420)
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        if let build = build, !build.isEmpty && build != version {
            return "Battry v\(version) (\(build))"
        } else {
            return "Battry v\(version)"
        }
    }
    
    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text(i18n.t("update.checking"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(i18n.t("update.latest"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .updateAvailable(let version, _):
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("v\(version) " + i18n.t("update.available.short"))
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        case .error(_):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(i18n.t("update.error"))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
}

/// Компонент для отображения ссылки с иконкой
struct AboutLinkView: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: String
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    AboutPanel(updateChecker: UpdateChecker())
        .frame(width: 380)
}
