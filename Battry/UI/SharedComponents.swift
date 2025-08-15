import SwiftUI

// MARK: - Shared UI Components

/// Улучшенная карточка статистики с современным дизайном
struct EnhancedStatCard: View {
    let title: String
    let value: String
    let icon: String?
    let badge: String?
    let badgeColor: Color
    let accentColor: Color
    
    init(
        title: String,
        value: String,
        icon: String? = nil,
        badge: String? = nil,
        badgeColor: Color = .secondary,
        accentColor: Color = Color.accentColor
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.badge = badge
        self.badgeColor = badgeColor
        self.accentColor = accentColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок с иконкой
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if let badge = badge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(badgeColor)
                }
            }
            
            // Значение
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Группирующий контейнер для связанных элементов
struct CardSection<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content
    
    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Современная кнопка-переключатель для периодов
struct PeriodButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// Кнопка выбора метрики для графиков
struct MetricToggleButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? color.opacity(0.15) : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// Информационная карточка для состояний калибровки
struct StatusCard<Actions: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let content: String?
    let actions: Actions?
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color,
        content: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
        self.actions = actions()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            
            if let content = content {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !(actions is EmptyView) {
                actions
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(iconColor.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Улучшенный прогресс-бар
struct EnhancedProgressView: View {
    let value: Double
    let total: Double
    let color: Color
    let height: CGFloat
    
    init(value: Double, total: Double, color: Color = Color.accentColor, height: CGFloat = 8) {
        self.value = value
        self.total = total
        self.color = color
        self.height = height
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: height)
                
                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * (value / total), height: height)
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// Разделитель с отступами
struct SpacedDivider: View {
    let padding: CGFloat
    
    init(padding: CGFloat = 8) {
        self.padding = padding
    }
    
    var body: some View {
        Divider()
            .padding(.vertical, padding)
    }
}