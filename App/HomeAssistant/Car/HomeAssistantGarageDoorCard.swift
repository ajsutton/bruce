import SwiftUI

struct HomeAssistantGarageDoorCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let door: HomeAssistantGarageDoorSnapshot
  let isLive: Bool
  let isRefreshing: Bool
  let mode: BruceMode
  let isLightChanging: Bool
  let isLockChanging: Bool
  let pendingDoorCommand: HomeAssistantGarageDoorCommand?
  let toggleLight: () -> Void
  let toggleLock: () -> Void
  let sendDoorCommand: (HomeAssistantGarageDoorCommand) -> Void

  @State private var isDoorActionArmed = false

  private var copy: GarageDoorCopy {
    GarageDoorCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      doorActionArea
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(borderColor, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
      radius: 10,
      y: 4
    )
    .animation(reduceMotion ? nil : .snappy, value: isDoorActionArmed)
    .animation(reduceMotion ? nil : .snappy, value: door.doorState)
    .task(id: isDoorActionArmed) {
      guard isDoorActionArmed else { return }
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      isDoorActionArmed = false
    }
    .onChange(of: door.doorState) {
      if door.doorState.isMoving {
        isDoorActionArmed = false
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      if canArmDoorAction {
        Button {
          isDoorActionArmed.toggle()
        } label: {
          doorStatus
        }
        .buttonStyle(.plain)
        .accessibilityLabel(door.name)
        .accessibilityValue(accessibilityValue(copy.doorState(door.doorState)))
        .accessibilityHint(
          isDoorActionArmed ? copy.hideDoorControls : copy.showDoorControls
        )
      } else {
        doorStatus
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(door.name)
          .accessibilityValue(accessibilityValue(copy.doorState(door.doorState)))
      }

      accessoryStatusIcons
    }
  }

  private var doorStatus: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: doorIcon)
        .font(.title2)
        .foregroundStyle(doorIconForeground)
        .frame(width: 44, height: 44)
        .background(iconBackground, in: RoundedRectangle(cornerRadius: 12))
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(door.name)
          .font(.headline)
          .foregroundStyle(primaryForeground)
        HStack(spacing: 6) {
          Text(copy.doorState(door.doorState))
          if door.doorState.isMoving {
            ProgressView()
              .controlSize(.mini)
              .accessibilityHidden(true)
          } else if canArmDoorAction {
            Image(systemName: isDoorActionArmed ? "chevron.up" : "chevron.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(secondaryForeground)
              .accessibilityHidden(true)
          }
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(primaryForeground)

        if !isLive {
          Text(isRefreshing ? copy.updating : copy.lastKnown)
            .font(.caption.weight(.medium))
            .foregroundStyle(secondaryForeground)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentShape(Rectangle())
  }

  private var accessoryStatusIcons: some View {
    HStack(spacing: 6) {
      statusButton(
        StatusButtonConfiguration(
          title: copy.light,
          value: lightText,
          icon: lightIcon,
          color: door.lightState == .illuminated ? .yellow : .secondary,
          isChanging: isLightChanging,
          isEnabled: door.lightEntityID != nil && door.lightState != .unavailable
        ),
        action: toggleLight
      )
      statusButton(
        StatusButtonConfiguration(
          title: copy.lock,
          value: lockText,
          icon: lockIcon,
          color: door.lockState == .locked ? .green : .secondary,
          isChanging: isLockChanging,
          isEnabled: door.lockEntityID != nil && door.lockState != .unavailable
        ),
        action: toggleLock
      )
    }
  }

  private func statusButton(
    _ configuration: StatusButtonConfiguration,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      DelayedGarageStatusIcon(
        icon: configuration.icon,
        isChanging: configuration.isChanging
      )
      .foregroundStyle(isLive || isRefreshing ? configuration.color : .secondary)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
      .background {
        Circle()
          .fill(mode.foregroundColor.opacity(colorScheme == .dark ? 0.12 : 0.05))
          .frame(width: 32, height: 32)
      }
    }
    .buttonStyle(.plain)
    .disabled(!isLive || !configuration.isEnabled || configuration.isChanging)
    .accessibilityLabel(configuration.title)
    .accessibilityValue(accessibilityValue(configuration.value))
    .help("\(configuration.title): \(configuration.value)")
  }

  private func accessibilityValue(_ value: String) -> String {
    guard !isLive else { return value }
    return "\(isRefreshing ? copy.updating : copy.lastKnown). \(value)"
  }

  @ViewBuilder
  private var doorActionArea: some View {
    if door.doorState.isMoving, door.supportsStop {
      Button {
        sendDoorCommand(.stop)
      } label: {
        actionLabel(
          copy.stopDoor,
          systemImage: "stop.fill",
          showsProgress: pendingDoorCommand == .stop
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(!isLive || pendingDoorCommand != nil)
      .accessibilityHint(copy.stopDoorHint)
    } else if let pendingDoorCommand {
      actionLabel(
        copy.pending(command: pendingDoorCommand),
        systemImage: nil,
        showsProgress: true
      )
    } else if isDoorActionArmed {
      switch door.doorState {
      case .closed:
        doorActionButton(copy.openDoor, command: .open)
      case .open:
        doorActionButton(copy.closeDoor, command: .close)
      case .partlyOpen:
        HStack {
          doorActionButton(copy.openFully, command: .open)
          doorActionButton(copy.closeDoor, command: .close)
        }
      case .opening, .closing, .unavailable:
        EmptyView()
      }
    }
  }

  private func doorActionButton(
    _ title: String,
    command: HomeAssistantGarageDoorCommand
  ) -> some View {
    Button {
      isDoorActionArmed = false
      sendDoorCommand(command)
    } label: {
      actionLabel(title, systemImage: doorActionIcon(command), showsProgress: false)
    }
    .buttonStyle(.bordered)
    .disabled(!isLive)
  }

  private func actionLabel(
    _ title: String,
    systemImage: String?,
    showsProgress: Bool
  ) -> some View {
    HStack(spacing: 8) {
      if showsProgress {
        ProgressView()
          .controlSize(.small)
      } else if let systemImage {
        Image(systemName: systemImage)
      }
      Text(title)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 32)
  }

  private var canArmDoorAction: Bool {
    isLive && pendingDoorCommand == nil
      && !door.doorState.isMoving && door.doorState != .unavailable
  }

  private func doorActionIcon(
    _ command: HomeAssistantGarageDoorCommand
  ) -> String {
    switch command {
    case .open: "arrow.up"
    case .close: "arrow.down"
    case .stop: "stop.fill"
    }
  }

  private struct StatusButtonConfiguration {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isChanging: Bool
    let isEnabled: Bool
  }
}

private struct DelayedGarageStatusIcon: View {
  let icon: String
  let isChanging: Bool

  @State private var showsProgress = false

  var body: some View {
    ZStack {
      Image(systemName: icon)
        .font(.body.weight(.medium))
        .opacity(showsProgress ? 0 : 1)
      ProgressView()
        .controlSize(.small)
        .opacity(showsProgress ? 1 : 0)
    }
    .task(id: isChanging) {
      showsProgress = false
      guard isChanging else { return }
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      showsProgress = true
    }
  }
}

extension HomeAssistantGarageDoorCard {
  private var doorIcon: String {
    switch door.doorState {
    case .open, .opening, .partlyOpen:
      "door.garage.open"
    case .closing, .closed:
      "door.garage.closed"
    case .unavailable:
      "door.garage.closed.trianglebadge.exclamationmark"
    }
  }

  private var lightIcon: String {
    switch door.lightState {
    case .illuminated: "lightbulb.fill"
    case .off: "lightbulb"
    case .unavailable: "lightbulb.slash"
    }
  }

  private var lockIcon: String {
    switch door.lockState {
    case .locked, .locking: "lock.fill"
    case .unlocked, .unlocking: "lock.open"
    case .unavailable: "lock.slash"
    }
  }

  private var lightText: String {
    switch door.lightState {
    case .illuminated: copy.lightOn
    case .off: copy.lightOff
    case .unavailable: copy.unavailable
    }
  }

  private var lockText: String {
    switch door.lockState {
    case .locked: copy.locked
    case .locking: copy.locking
    case .unlocking: copy.unlocking
    case .unlocked: copy.unlocked
    case .unavailable: copy.unavailable
    }
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  private var doorIconForeground: Color {
    switch door.doorState {
    case .open, .opening, .closing, .partlyOpen:
      .orange
    case .closed:
      mode.isFullBruce ? mode.backgroundColor : mode.foregroundColor
    case .unavailable:
      .secondary
    }
  }

  private var iconBackground: Color {
    mode.isFullBruce
      ? mode.accentColor
      : colorScheme == .dark
        ? mode.foregroundColor.opacity(0.72)
        : Color.white.opacity(0.82)
  }

  private var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  private var borderColor: Color {
    if mode.isFullBruce {
      return mode.accentColor.opacity(0.28)
    }
    return colorScheme == .dark
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(0.08)
  }
}
