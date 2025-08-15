# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Battry is a native macOS menu bar application for monitoring MacBook battery health, collecting history, visualizing charts, performing advanced battery analysis, and generating HTML reports. The app is written in Swift/SwiftUI and uses IOKit for low-level battery data access.

## Development Commands

### Build and Run
- **Build**: Open `Battry.xcodeproj` in Xcode and press ⌘B
- **Run**: Press ⌘R in Xcode to build and run the app
- **Clean Build**: Press ⌘⇧K in Xcode

### Requirements
- macOS 13.0+ (uses Swift Charts)
- Xcode 15.x+ (Swift 5.9+)
- No external dependencies (pure SwiftUI/IOKit)

### Testing
Currently no unit tests are implemented. The app requires manual testing on a MacBook with battery.

## Architecture

### Data Flow
```
IOKit → BatteryService → BatteryViewModel → HistoryStore
                              ↓                    ↓
                        CalibrationEngine    AnalyticsEngine
                              ↓                    ↓
                            UI Panels      Report Generation
```

### Core Components

#### Battery Data Collection
- **BatteryService.swift**: Low-level IOKit interface for reading battery state
  - Reads from IOPowerSources and AppleSmartBattery IORegistry
  - Returns `BatterySnapshot` with percentage, charging status, capacity, cycles, temperature
  - Handles devices without battery (Mac mini/Studio)

#### State Management
- **BatteryViewModel.swift**: Observable model that polls battery state every 30 seconds
  - Publishes state changes via `@Published` property
  - Formats display values for UI
  - Provides `PassthroughSubject` publisher for other components

- **HistoryStore.swift**: Persistent storage for battery measurements
  - Saves to `~/Library/Application Support/Battry/history.json`
  - Implements data trimming: full detail for 7 days, 5-min aggregation for 7-30 days, deletes >30 days
  - Provides data for charts and analytics

#### Analytics
- **AnalyticsEngine.swift**: Calculates battery health metrics
  - Average and trend discharge rate (%/h) using linear regression
  - Health score (0-100) based on wear, cycles, temperature, micro-drops
  - Detects "micro-drops" (≥2% drop in ≤120s without charging)
  - Generates recommendations (monitor/replace)
  - Uses median filtering for data smoothing

- **CalibrationEngine.swift**: Manages battery endurance test sessions
  - States: idle → waitingFull → running → paused/completed
  - Auto-starts at 100% on battery, completes at 5%
  - Saves results to `~/Library/Application Support/Battry/calibration.json`
  - Maintains history of last 5 sessions
  - Auto-resets on data gaps >5 minutes

#### UI Components
- **BattryApp.swift**: Main app entry point, sets up menu bar extra
- **MenuContent.swift**: Tab-based UI with Overview/Charts/Calibration/Settings panels
- **ChartsPanel.swift**: Visualizes battery history using Swift Charts
- **CalibrationPanel.swift**: Controls and displays battery test progress
- **SettingsPanel.swift**: Shows data storage info and prevent sleep toggle
- **ReportGenerator.swift**: Creates HTML reports with SVG sparklines

#### Localization
- **Localization.swift**: Language switching (RU/EN) with auto-detection
- Localized strings in `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`

### Data Storage
- `~/Library/Application Support/Battry/`
  - `history.json`: Time series of battery measurements
  - `calibration.json`: Test session state and results
- Temporary HTML reports in `NSTemporaryDirectory()`

## Key Implementation Notes

1. **Battery Detection**: Currently uses IOPowerSources transport type, which may incorrectly detect UPS as battery. Consider checking for `kIOPSInternalBatteryType` specifically.

2. **History Recording**: Triggered by `onChange(of: battery.state)` which may miss updates if values don't change. Consider timer-based recording for consistent time series.

3. **Calibration Sessions**: Require continuous discharge from 100% to 5%. Auto-resets if app closes or data gap >5 minutes. Prevents system sleep during active test.

4. **Micro-drop Detection**: Looks for ≥2% drops in ≤120s (4 samples at 30s intervals). May have false positives on noisy sensors.

5. **Health Score Calculation**: Penalizes for wear%, cycles>500, temp>40°C, and micro-drops. Thresholds are hardcoded.

## Code Style Guidelines

- Pure SwiftUI for UI components
- No external dependencies
- IOKit for system-level battery access
- Observable pattern using `@Published` and `PassthroughSubject`
- JSON for data persistence
- Localization support for RU/EN

## Important Files to Review

When making changes, pay attention to:
- Data flow between ViewModels and Stores
- IOKit API usage in BatteryService
- State management in CalibrationEngine
- Data trimming logic in HistoryStore
- Regression calculations in AnalyticsEngine