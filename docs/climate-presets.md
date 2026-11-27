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

The air conditioner icon controls power independently of the mode dropdown.
Selecting a mode while the air conditioner is off leaves it off; tapping the
icon then starts it in the selected mode. The dropdown retains the last
confirmed active mode when switching off. Bruce saves this mode, or a mode
chosen while off, on this device for each Home Assistant server and air
conditioner. Cooling is the fallback when no supported mode has been saved;
systems without Cooling use their first advertised mode. Stale cached updates
and unconfirmed mode commands do not replace the saved active mode.
