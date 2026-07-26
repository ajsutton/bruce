# Bruce

Bruce is a native iPhone and Mac client for a Home Assistant-backed home. It defaults to a calm,
quietly premium presentation and includes an opt-in **Go The Full Bruce** mode that changes its
icon, styling and voice together.

Product functionality is added incrementally around specific household use cases.

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

`Bruce.xcodeproj` is generated from `project.yml` and is not committed.

The iOS commands prefer an iOS 26 simulator. Set `IOS_RUNTIME_MAJOR` to choose another installed
runtime, or `IOS_SIMULATOR_ID` to select an exact simulator.

## Local network development

Bruce normally relies on the macOS Local Network permission when connecting to Home Assistant.
macOS can become confused when multiple development builds of the same app have been launched.

For a smoother day-to-day development loop, macOS 15.5 and later can exempt a development subnet
from Local Network privacy. This is optional and applies to every program on the Mac, so use it
only on a trusted development network. For example, the current `YOUR_DEVELOPMENT_SUBNET` Wi-Fi subnet can
be allowed with:

```sh
sudo defaults write com.apple.network.local-network \
  AllowedWiFiLocalNetworkAddresses -array "YOUR_DEVELOPMENT_SUBNET"
```

Use `AllowedEthernetLocalNetworkAddresses` instead when developing over Ethernet. Restart macOS
after changing either preference.

Do not use this exemption to validate Bruce's permission flow. Apple does not provide a supported
way to reset Local Network privacy on macOS; use a disposable macOS user account or a virtual
machine snapshot when testing first-run, denial and recovery behaviour.
