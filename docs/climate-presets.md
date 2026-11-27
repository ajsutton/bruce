# Climate presets

Bruce builds climate presets from Home Assistant's AirTouch zones:

- **All** includes every zone eligible for presets.
- Floor presets use the floor of the zone's Home Assistant area. An entity's
  explicit area takes precedence over its device's area.
- Labels starting with `Climate Preset:` create custom presets, using the text
  after the colon as the name. The prefix is case insensitive. Labels can be
  assigned to the entity, its device, or its area.
- **None** turns all zones off.

`Climate Preset: Exclude` is reserved. A zone with this label is omitted from
All, floor, and custom preset membership; it does not create an Exclude button.
Applying a preset turns member zones on and nonmembers, including excluded
zones, off. Manual power, temperature, and vent controls remain available.

Labels configure membership, not temperatures or vent opening percentages.
Changing labels in Home Assistant updates Bruce through its live registry
subscription.
