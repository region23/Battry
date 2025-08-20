import SwiftUI

/// Инлайн компонент выбора пресета мощности (упрощенная версия без обертки)
struct InlinePowerPresetSelector: View {
    @Binding var selectedPreset: PowerPreset
    let designCapacityMah: Int
    @ObservedObject private var i18n = Localization.shared
    
    /// Вычисленные целевые мощности для всех пресетов
    private var targetPowers: [PowerPreset: Double] {
        PowerCalculator.allTargetPowers(designCapacityMah: designCapacityMah)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок
            HStack(spacing: 6) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(i18n.t("power.preset.selection"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Компактные пресеты в стиле капсул как в обзоре
            HStack(spacing: 6) {
                ForEach(PowerPreset.allCases) { preset in
                    compactPresetButton(for: preset)
                }
            }
        }
    }
    
    @ViewBuilder
    private func inlinePresetButton(for preset: PowerPreset) -> some View {
        let isSelected = selectedPreset == preset
        let targetPower = targetPowers[preset] ?? 5.0
        
        Button {
            selectedPreset = preset
        } label: {
            VStack(spacing: 4) {
                // Первая строка: Иконка + Мощность
                HStack(spacing: 4) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                    Text("\(String(format: "%.0f", targetPower))W")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                
                // Вторая строка: Название пресета + время
                VStack(spacing: 1) {
                    Text(i18n.t(preset.localizationKey))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                    
                    Text("~\(QuickHealthTest.estimatedTestTime(for: preset)) мин")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Color.accentColor.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.description)
    }
    
    @ViewBuilder
    private func compactPresetButton(for preset: PowerPreset) -> some View {
        let isSelected = selectedPreset == preset
        let targetPower = targetPowers[preset] ?? 5.0
        
        Button {
            selectedPreset = preset
        } label: {
            HStack(spacing: 3) {
                Image(systemName: preset.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.0f", targetPower))W")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("~\(QuickHealthTest.estimatedTestTime(for: preset))м")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : preset.backgroundColor,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .help(preset.description)
    }
}

/// UI компонент для выбора пресета мощности
struct PowerPresetSelector: View {
    @Binding var selectedPreset: PowerPreset
    let designCapacityMah: Int
    @ObservedObject private var i18n = Localization.shared
    
    /// Вычисленные целевые мощности для всех пресетов
    private var targetPowers: [PowerPreset: Double] {
        PowerCalculator.allTargetPowers(designCapacityMah: designCapacityMah)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок
            HStack(spacing: 6) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(i18n.t("power.preset.selection"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Пресеты
            HStack(spacing: 8) {
                ForEach(PowerPreset.allCases) { preset in
                    presetButton(for: preset)
                }
            }
            
            // Информация о выбранном пресете
            if let targetPower = targetPowers[selectedPreset] {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(i18n.t("target.power")): \(String(format: "%.1f", targetPower))W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(\(selectedPreset.rawValue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private func presetButton(for preset: PowerPreset) -> some View {
        let isSelected = selectedPreset == preset
        let targetPower = targetPowers[preset] ?? 5.0
        
        Button {
            selectedPreset = preset
        } label: {
            VStack(spacing: 4) {
                // Первая строка: Иконка + Мощность
                HStack(spacing: 4) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                    Text("\(String(format: "%.0f", targetPower))W")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                
                // Вторая строка: Название пресета
                Text(i18n.t(preset.localizationKey))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Color.accentColor.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.description)
    }
}

/// Компонент для отображения качества контроля мощности
struct PowerControlQualityIndicator: View {
    let quality: Double // 0-100
    let isActive: Bool
    @ObservedObject private var i18n = Localization.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Иконка состояния
            Image(systemName: statusIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
            
            // Текст качества
            VStack(alignment: .leading, spacing: 2) {
                Text(i18n.t("power.control.quality"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if isActive {
                    Text("\(Int(quality))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
    
    private var statusIcon: String {
        if !isActive {
            return "minus.circle"
        } else if quality >= 80 {
            return "checkmark.circle"
        } else if quality >= 60 {
            return "exclamationmark.triangle"
        } else {
            return "xmark.circle"
        }
    }
    
    private var statusColor: Color {
        if !isActive {
            return .secondary
        } else if quality >= 80 {
            return .green
        } else if quality >= 60 {
            return .orange
        } else {
            return .red
        }
    }
}

/// Компонент для отображения информации о температурной нормализации
struct TemperatureNormalizationInfo: View {
    let originalSOH: Double
    let normalizedSOH: Double
    let averageTemperature: Double
    let quality: Double
    @ObservedObject private var i18n = Localization.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(temperatureColor)
                Text(i18n.t("temperature.normalization"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 16) {
                // Оригинальное значение
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.t("original.label"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", originalSOH))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                // Стрелка
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                // Нормализованное значение
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.t("temp.at.25c"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", normalizedSOH))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(normalizedSOH > originalSOH ? .red : .blue)
                }
                
                Spacer()
                
                // Температура теста
                VStack(alignment: .trailing, spacing: 2) {
                    Text(i18n.t("test.temp"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f°C", averageTemperature))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(temperatureColor)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var temperatureColor: Color {
        if averageTemperature < 20 {
            return .blue
        } else if averageTemperature > 35 {
            return .red
        } else {
            return .green
        }
    }
}

#if DEBUG
struct PowerPresetSelector_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PowerPresetSelector(
                selectedPreset: .constant(.medium),
                designCapacityMah: 6075
            )
            
            PowerControlQualityIndicator(
                quality: 85.0,
                isActive: true
            )
            
            TemperatureNormalizationInfo(
                originalSOH: 79.6,
                normalizedSOH: 81.2,
                averageTemperature: 32.4,
                quality: 85.0
            )
        }
        .padding()
        .frame(maxWidth: 400)
    }
}
#endif