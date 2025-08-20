import SwiftUI
import AppKit

/// Вкладка настроек
struct SettingsPanel: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var i18n: Localization = .shared
    @State private var showClearDataConfirm: Bool = false
    @State private var isTemperatureExpanded: Bool = false
    @AppStorage("settings.showPercentageInMenuBar") private var showPercentageInMenuBar: Bool = true
    @AppStorage("settings.showIconInDock") private var showIconInDock: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Основные настройки
                ModernSettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ModernSettingsHeader(
                            title: i18n.t("settings.general"),
                            icon: "gearshape.fill",
                            color: .blue
                        )
                        
                        VStack(spacing: 8) {
                            ModernSettingsRow {
                                HStack {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    Text(i18n.t("settings.language"))
                                        .font(.system(.body, weight: .medium))
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
                            .help(i18n.t("settings.language.description"))
                            
                            ModernSettingsRow {
                                HStack {
                                    Image(systemName: "percent")
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    Text(i18n.t("settings.show.percentage"))
                                        .font(.system(.body, weight: .medium))
                                    Spacer()
                                    Toggle("", isOn: $showPercentageInMenuBar)
                                        .labelsHidden()
                                        .tint(.blue)
                                }
                            }
                            .help(i18n.t("settings.show.percentage.description"))
                            
                            ModernSettingsRow {
                                HStack {
                                    Image(systemName: "dock.rectangle")
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    Text(i18n.t("settings.show.dock.icon"))
                                        .font(.system(.body, weight: .medium))
                                    Spacer()
                                    Toggle("", isOn: $showIconInDock)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .onChange(of: showIconInDock) { _, newValue in
                                            updateDockIconVisibility(newValue)
                                        }
                                }
                            }
                            .help(i18n.t("settings.show.dock.icon.description"))
                        }
                    }
                }
                
                // Температурная нормализация
                ModernSettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isTemperatureExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                ModernSettingsHeader(
                                    title: i18n.language == .ru ? "Температурная нормализация" : "Temperature Normalization",
                                    icon: "thermometer.variable",
                                    color: .orange
                                )
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isTemperatureExpanded ? 90 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Краткое объяснение всегда видимо
                        Text(i18n.language == .ru ? "Автоматическая корректировка результатов тестов батареи с учётом температуры для точного сравнения" : "Automatic correction of battery test results considering temperature for accurate comparison")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        let coeffs = TemperatureNormalizer.currentCoefficients()
                        let observationCount = TemperatureNormalizer.observationCount()
                        
                        // Статус обучения
                        StatusIndicator(
                            status: observationCount > 10 ? .active : .learning,
                            text: observationCount > 10 ? 
                                (i18n.language == .ru ? "Активна • \(observationCount) наблюдений" : "Active • \(observationCount) observations") :
                                (i18n.language == .ru ? "Обучается • \(observationCount) наблюдений" : "Learning • \(observationCount) observations")
                        )
                        
                        if isTemperatureExpanded {
                            VStack(spacing: 10) {
                                DetailRow(
                                    title: "SOH (%/°C)",
                                    value: String(format: "%.3f", coeffs.sohPerDegree),
                                    helpText: i18n.language == .ru ? "Коррекция ёмкости по температуре" : "Capacity correction by temperature"
                                )
                                
                                DetailRow(
                                    title: "DCIR (%/°C)",
                                    value: String(format: "%.3f", coeffs.dcirPerDegree),
                                    helpText: i18n.language == .ru ? "Коррекция сопротивления по температуре" : "Resistance correction by temperature"
                                )
                                
                                DetailRow(
                                    title: i18n.language == .ru ? "Диапазон" : "Range",
                                    value: String(format: "%.0f–%.0f°C", coeffs.minTemperature, coeffs.maxTemperature),
                                    helpText: i18n.language == .ru ? "Рабочий диапазон температур" : "Operating temperature range"
                                )
                                
                                HStack {
                                    Spacer()
                                    Button {
                                        TemperatureNormalizer.resetSelfLearning()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.counterclockwise")
                                            Text(i18n.language == .ru ? "Сбросить коэффициенты" : "Reset coefficients")
                                        }
                                        .font(.caption)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                
                // Управление данными
                ModernSettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ModernSettingsHeader(
                            title: i18n.t("settings.data"),
                            icon: "externaldrive.fill",
                            color: .green
                        )
                        
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(i18n.t("settings.data.entries.label"))
                                        .font(.system(.body, weight: .medium))
                                    Text("\(history.itemsCount) записей")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(i18n.t("settings.data.size.label"))
                                        .font(.system(.body, weight: .medium))
                                    Text(readableSize(totalBytes))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            HStack(spacing: 12) {
                                Button {
                                    openDataFolder()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                        Text(i18n.t("settings.data.open.folder"))
                                    }
                                    .font(.system(.body, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .help(i18n.t("settings.data.open.folder.description"))
                                
                                Button(role: .destructive) {
                                    showClearDataConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash.fill")
                                        Text(i18n.t("settings.data.clear"))
                                    }
                                    .font(.system(.body, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .alert(i18n.t("settings.data.clear"), isPresented: $showClearDataConfirm) {
            Button(i18n.t("reset"), role: .destructive) {
                clearAllData()
            }
            Button(i18n.t("cancel"), role: .cancel) {}
        } message: {
            Text(i18n.t("settings.data.confirm"))
        }
    }

    private func clearAllData() {
        history.clearAll()
        calibrator.clearPersistentData()
    }
    
    private func openDataFolder() {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dataDir = base.appendingPathComponent("Battry", isDirectory: true)
        NSWorkspace.shared.open(dataDir)
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
    
    private func updateDockIconVisibility(_ show: Bool) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(show ? .regular : .accessory)
        }
    }
}

private extension HistoryStore {
    var itemsCount: Int { items.count }
}

// MARK: - Modern Settings UI Components

struct ModernSettingsCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ModernSettingsHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct SettingsHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.bottom, 2)
    }
}

struct ModernSettingsRow<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
    }
}

struct CompactSettingsRow<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content
        }
        .padding(.vertical, 2)
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

struct StatusIndicator: View {
    enum Status {
        case active, learning, inactive
        
        var color: Color {
            switch self {
            case .active: return .green
            case .learning: return .orange
            case .inactive: return .gray
            }
        }
    }
    
    let status: Status
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(status.color.opacity(0.1))
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    let helpText: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(.body, weight: .medium))
                .help(helpText)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CompactLabel: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
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



