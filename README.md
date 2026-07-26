# Smart Home

Native iPhone and Mac clients for a Home Assistant-backed smart home.

This repository currently contains project infrastructure only. Product functionality will be
added incrementally around specific household use cases.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- `just`
- XcodeGen
- swift-format
- SwiftLint

Install the command-line tools with Homebrew:

```sh
brew install just xcodegen swift-format swiftlint
```

## Common commands

```sh
just generate
just open
just build
just test
just format
just format-check
```

The Xcode project is generated from `project.yml` and is not committed.

The iOS commands prefer an iOS 26 simulator. Set `IOS_RUNTIME_MAJOR` to choose another installed
runtime, or `IOS_SIMULATOR_ID` to select an exact simulator.
