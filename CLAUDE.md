# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Battry is a native macOS menu bar application for battery monitoring and autonomy analysis. It's built with SwiftUI and uses IOKit to access battery information directly from the system.

## Build Commands

### Development
```bash
# Open project in Xcode
open Battry.xcodeproj

# Build from command line
xcodebuild -project Battry.xcodeproj -scheme Battry -configuration Debug build

# Release build
xcodebuild -project Battry.xcodeproj -scheme Battry -configuration Release build

# Create archive for distribution
xcodebuild -project Battry.xcodeproj -scheme Battry -configuration Release -archivePath build/Battry.xcarchive archive
```

### Testing
This project currently has no unit tests. When adding tests:
- Create test target in Xcode
- Use XCTest framework
- Test core engines: AnalyticsEngine, CalibrationEngine, LoadGenerator

## Architecture

### Core Data Flow
```
IOKit/IORegistry → BatteryService → BatteryViewModel → UI Components
                                         ↓
                                   HistoryStore → AnalyticsEngine
                                         ↓
                                 CalibrationEngine → LoadGenerator/VideoLoadEngine
                                         ↓
                                   LoadSafetyGuard
```

### Key Components

- **BatteryService**: Direct IOKit interface for battery data (percentage, capacity, cycles, temperature, voltage)
- **BatteryViewModel**: Main @StateObject with Combine publisher, 30s polling (5s in fast mode)
- **HistoryStore**: JSON persistence with automatic data trimming (7 days full detail, 7-30 days aggregated)
- **CalibrationEngine**: Manages battery discharge tests with automatic start/stop logic
- **AnalyticsEngine**: Health scoring algorithm (0-100) with wear analysis and recommendations
- **LoadGenerator**: CPU stress testing with configurable profiles (light/medium/heavy)
- **VideoLoadEngine**: GPU stress via 1080p video playback with fallback handling
- **LoadSafetyGuard**: Safety system that stops load generation based on battery/temperature thresholds
- **ReportGenerator**: Creates HTML reports with embedded uPlot charts

### UI Structure
- **MenuContent**: Main SwiftUI container with tab navigation
- **SharedComponents**: Reusable UI elements like EnhancedStatCard
- **Panels**: CalibrationPanel, ChartsPanel (Swift Charts), SettingsPanel, AboutPanel

## File Structure

- **Battry/**: Main source directory
- **Assets.xcassets/**: App icons and custom battery/charge icons
- **ReportAssets/**: HTML report dependencies (uPlot.js, CSS)
- **Localization**: en.lproj/ and ru.lproj/ for bilingual support
- **Releases/**: Built app packages by version

## Development Patterns

### State Management
- Use @StateObject for main data models (BatteryViewModel, HistoryStore, etc.)
- @ObservedObject for passed dependencies
- Combine publishers for reactive data flow
- @MainActor for UI-related classes

### Data Persistence
- JSON files in ~/Library/Application Support/Battry/
- history.json: Battery telemetry with automatic cleanup
- calibration.json: Test results and state

### Localization
- Localization.swift provides centralized string management
- Use L.t("key") pattern for translated strings
- Support for Russian and English with auto-detection

### Safety Considerations
- LoadSafetyGuard monitors: battery level (≤7%), temperature (>35°C), power source changes
- Automatic sleep prevention during calibration tests
- Graceful degradation when video files missing

## Technical Requirements

- **macOS**: 14.6+
- **Xcode**: 15.0+
- **Swift**: 5.0+
- **Deployment Target**: macOS 14.6
- **Bundle ID**: region23.Battry
- **Current Version**: 3.0.1

## Dependencies

This project uses only Apple frameworks:
- SwiftUI (UI)
- Combine (Reactive programming)
- IOKit (Battery data access)
- Charts (Data visualization)
- AVFoundation (Video playback for GPU load)
- AppKit (Menu bar integration)

No external package managers or third-party libraries.