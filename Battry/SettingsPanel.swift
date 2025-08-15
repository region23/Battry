import SwiftUI

/// Вкладка настроек
struct SettingsPanel: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var i18n: Localization = .shared

    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(i18n.t("settings.language"))
                    Picker("", selection: $i18n.language) {
                        ForEach(AppLanguage.allCases) { l in
                            Text(l.label).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                GridRow {
                    Text(i18n.t("settings.prevent.sleep"))
                    Toggle("", isOn: $calibrator.preventSleepDuringTesting)
                        .labelsHidden()
                        .help(i18n.t("settings.prevent.sleep"))
                }
            }
            .environment(\.controlSize, .small)

            Divider()

            Text(i18n.t("settings.data")).font(.subheadline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text(i18n.t("settings.data.entries.label"))
                    Text("\(history.itemsCount)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text(i18n.t("settings.data.size.label"))
                    Text(readableSize(totalBytes))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("")
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label(i18n.t("settings.data.clear"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .confirmationDialog(i18n.t("settings.data.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                            Button(i18n.t("reset"), role: .destructive) { clearAllData() }
                            Button(i18n.t("cancel"), role: .cancel) { }
                        }
                    }
                }
            }
            .environment(\.controlSize, .small)
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



