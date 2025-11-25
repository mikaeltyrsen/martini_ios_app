# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Martini is an iOS application built with SwiftUI, targeting iOS 17.5+. The project uses Swift 5.0 and supports both iPhone and iPad (device families 1,2).

**Bundle Identifier**: `com.martini.Martini`

## Build & Development Commands

### Building
```bash
# Build the project for iOS simulator
xcodebuild -scheme Martini -sdk iphonesimulator -configuration Debug build

# Build for iOS device
xcodebuild -scheme Martini -sdk iphoneos -configuration Debug build

# Build for Release
xcodebuild -scheme Martini -configuration Release build

# Clean build artifacts
xcodebuild -scheme Martini clean
```

### Running
```bash
# Open in Xcode (preferred for iOS development)
open Martini.xcodeproj

# List available simulators
xcrun simctl list devices available

# Build and run on a specific simulator
xcodebuild -scheme Martini -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme Martini -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test
xcodebuild test -scheme Martini -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MartiniTests/TestClassName/testMethodName
```

### Code Quality
```bash
# Format Swift code (requires swift-format to be installed)
swift-format -i -r Martini/

# Lint Swift code (requires SwiftLint to be installed)
swiftlint lint

# Auto-fix linting issues
swiftlint --fix
```

## Project Architecture

### Structure
This is a standard SwiftUI iOS app with the following structure:

- **Martini/** - Main application source code
  - `MartiniApp.swift` - App entry point with `@main` attribute
  - `ContentView.swift` - Root view of the application
  - **Assets.xcassets/** - Image and color assets
  - **Preview Content/** - SwiftUI preview assets

### SwiftUI Architecture
The app follows SwiftUI's declarative architecture:
- **App lifecycle**: Managed by `MartiniApp` struct conforming to the `App` protocol
- **View composition**: Views are composed using SwiftUI's `View` protocol
- **State management**: Uses SwiftUI's property wrappers (`@State`, `@Binding`, `@ObservedObject`, etc.)

### Adding New Features
When adding new functionality:
1. Create new Swift files in the `Martini/` directory
2. Organize related views in subdirectories (e.g., `Martini/Views/`, `Martini/Models/`)
3. Add new assets to `Assets.xcassets`
4. Update `ContentView.swift` or create new navigation flows as needed

### Xcode Project Management
- The project file is `Martini.xcodeproj/project.pbxproj`
- When adding new files, they must be added both to the filesystem and to the Xcode project
- Use Xcode's "Add Files to..." menu option or update the project file programmatically

## Development Notes

### Minimum Deployment Target
iOS 17.5+ - ensure all APIs and features used are compatible with this version.

### Swift Version
Swift 5.0 - the project uses modern Swift features available in this version.

### Device Support
Universal app supporting both iPhone (1) and iPad (2) device families.

### Git Workflow
The `.gitignore` is configured to exclude:
- Build artifacts (`DerivedData/`, `build/`)
- User-specific Xcode data (`*.xcuserdata/`, `*.xcuserstate`)
- System files (`.DS_Store`)
