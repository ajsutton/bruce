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

## Voice conversations

Choose **Talk to Bruce** at the bottom of the Mac sidebar or open the iPhone **Voice** tab, sign in through the existing OpenClaw website when prompted, and
select an agent. The picker and active call show the gateway's configured names and photos.
Every call starts a new conversation; Bruce has no conversation-history screen. Mute and End
control the voice connection. On Mac, the active call stays at the bottom of the sidebar. On iPhone, the Voice tab contains
the agent picker and active call. Switching tabs or apps, or locking the phone, keeps an
established call active; return using the Voice tab. iPhone calls also use the system call
interface, including lock-screen Mute and End controls. Hanging up returns to the agent picker
on both platforms. System audio interruptions or an unrecoverable connection failure end the call.

Voice uses the existing gateway at `https://bruce.thesuttons.name`, its Talk provider/model/voice,
and gateway-controlled direct WebRTC. The deployed GPT-Live Codex route uses the existing
ChatGPT subscription. Bruce does not configure providers, change agent instructions, or embed
provider credentials. Cloudflare Access sign-in and device keys are stored in the device's
Keychain, separately from Home Assistant. No developer `.agent-tokens` values are bundled.

The gateway must support `talk.client.create` with `gateway-control-v1`. Audio flows directly
between the device and the voice provider; the gateway owns agent execution and call control.
The native Access transfer implementation is adapted from OpenClaw under its MIT licence;
see `App/Resources/OpenClaw-LICENSE.txt`. WebRTC and Sodium versions are pinned in `project.yml`.

## Siri and Shortcuts

After connecting Bruce to Home Assistant, its energy and EV charging actions are available in
Shortcuts and through Siri. For example:

- “What’s the current solar generation in Bruce?” (or “PV generation”)
- “What’s the current battery level in Bruce?”
- “What’s the current electricity usage in Bruce?”
- “What’s the EV charger mode in Bruce?”
- “What’s the EV charger status in Bruce?”
- “Set the EV charger in Bruce to Smart Charging.”

The other charger modes are **Off** and **On**. Setting a mode requires device authentication.
On requests charging; it does not mean an unplugged or waiting vehicle has started charging.
Battery level means the home battery, and electricity usage means instantaneous home consumption
in kilowatts. Solar generation is also returned in kilowatts, and battery level in percent.
Every invocation fetches Home Assistant state; unavailable readings are reported as unavailable.
AC and garage-door Siri access remain with HomeKit.

These are App Intents with registered App Shortcuts, supported on iOS 26 and later. Apple’s
[published Siri schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains)
do not include energy or EV controls. Use the registered phrases with the installed app’s name
(“Bruce Debug” for a debug build); unrestricted iOS 27 Siri AI paraphrasing is not guaranteed.
Voice recognition and background execution should be verified on a signed physical-device build,
including with Bruce closed, an unreachable server, and an unavailable sensor.

## Local network development

Bruce normally relies on the macOS Local Network permission when connecting to Home Assistant.
macOS can become confused when multiple development builds of the same app have been launched.

For a smoother day-to-day development loop, macOS 15.5 and later can exempt a development subnet
from Local Network privacy. This is optional and applies to every program on the Mac, so use it
only on a trusted development network. Replace `YOUR_DEVELOPMENT_SUBNET` with the subnet to allow:

```sh
sudo defaults write com.apple.network.local-network \
  AllowedWiFiLocalNetworkAddresses -array "YOUR_DEVELOPMENT_SUBNET"
```

Use `AllowedEthernetLocalNetworkAddresses` instead when developing over Ethernet. Restart macOS
after changing either preference.

Do not use this exemption to validate Bruce's permission flow. Apple does not provide a supported
way to reset Local Network privacy on macOS; use a disposable macOS user account or a virtual
machine snapshot when testing first-run, denial and recovery behaviour.
