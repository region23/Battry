import SwiftUI

/// Вкладка настроек
struct SettingsPanel: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var i18n: Localization = .shared

    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Язык
            GroupBox {
                HStack {
                    Picker("", selection: $i18n.language) {
                        ForEach(AppLanguage.allCases) { l in
                            Text(l.label).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                    Spacer()
                }
                .padding(.top, 4)
            } label: { Text(i18n.t("settings.language")) }

            // Не засыпать во время теста
            GroupBox {
                Toggle(isOn: $calibrator.preventSleepDuringTesting) { Text("") }
                    .onChange(of: calibrator.preventSleepDuringTesting) { _, _ in
                        // Сразу применить: обновление произойдёт в движке при следующем изменении состояния
                    }
                    .padding(.top, 4)
            } label: { Text(i18n.t("settings.prevent.sleep")) }

            // Данные
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(i18n.t("settings.data.entries").replacingOccurrences(of: "%d", with: "\(history.itemsCount)"))
                        Spacer()
                        Text(i18n.t("settings.data.size").replacingOccurrences(of: "%@", with: readableSize(totalBytes)))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label(i18n.t("settings.data.clear"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .confirmationDialog(i18n.t("settings.data.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                            Button(i18n.t("reset"), role: .destructive) {
                                clearAllData()
                            }
                            Button(i18n.t("cancel"), role: .cancel) { }
                        }
                    }
                }
                .padding(.top, 4)
            } label: { Text(i18n.t("settings.data")) }
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


