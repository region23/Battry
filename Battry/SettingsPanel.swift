import SwiftUI
import AppKit

/// Вкладка настроек
struct SettingsPanel: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var i18n: Localization = .shared
    @State private var showClearDataConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Секция основных настроек
            SettingsSection {
                SettingsHeader(title: i18n.t("settings.general"), icon: "gearshape")
                
                VStack(spacing: 12) {
                    SettingsRow {
                        SettingsLabel(
                            title: i18n.t("settings.language"),
                            icon: "globe",
                            description: i18n.t("settings.language.description")
                        )
                        Spacer()
                        Picker("", selection: $i18n.language) {
                            ForEach(AppLanguage.allCases) { l in
                                Text(l.label).tag(l)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    
                }
            }
            
            // Секция управления данными
            SettingsSection {
                SettingsHeader(title: i18n.t("settings.data"), icon: "externaldrive")
                
                VStack(spacing: 12) {
                    SettingsRow {
                        SettingsLabel(
                            title: i18n.t("settings.data.entries.label"),
                            icon: "list.number",
                            description: i18n.t("settings.data.entries.description")
                        )
                        Spacer()
                        Text("\(history.itemsCount)")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    SettingsRow {
                        SettingsLabel(
                            title: i18n.t("settings.data.size.label"),
                            icon: "externaldrive",
                            description: i18n.t("settings.data.size.description")
                        )
                        Spacer()
                        Text(readableSize(totalBytes))
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Опасная зона - удаление данных
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(i18n.t("settings.data.danger.zone"), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    
                    Button(role: .destructive) {
                        showClearDataConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text(i18n.t("settings.data.clear"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .confirmationDialog(
            i18n.t("settings.data.clear"),
            isPresented: $showClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button(i18n.t("reset"), role: .destructive) { clearAllData() }
            Button(i18n.t("cancel"), role: .cancel) { }
        } message: {
            Text(i18n.t("settings.data.confirm"))
        }
    }

    private func clearAllData() {
        history.clearAll()
        calibrator.clearPersistentData()
    }
    
    

    private var totalBytes: Int64 {
        return history.fileSizeBytes + calibrator.fileSizeBytes
    }

    private func readableSize(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b < 1024 { return String(format: "%.0f B", b) }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}

private extension HistoryStore {
    var itemsCount: Int { items.count }
}

// MARK: - Settings UI Components

struct SettingsSection<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.bottom, 4)
    }
}

struct SettingsRow<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content
        }
        .padding(.vertical, 4)
    }
}

struct SettingsLabel: View {
    let title: String
    let icon: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
        }
    }
}



