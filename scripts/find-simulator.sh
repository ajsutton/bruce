#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${IOS_SIMULATOR_ID:-}" ]]; then
  echo "$IOS_SIMULATOR_ID"
  exit 0
fi

xcrun simctl list devices available -j \
  | python3 -c "
import json
import re
import sys

data = json.load(sys.stdin)
preferred_major = int('${IOS_RUNTIME_MAJOR:-26}')
candidates = []

for runtime, devices in data.get('devices', {}).items():
    match = re.search(r'iOS-(\d+)', runtime)
    if not match:
        continue
    major = int(match.group(1))
    for device in devices:
        name = device.get('name', '')
        if 'iPhone' not in name:
            continue
        score = (
            major == preferred_major,
            'Pro' in name and 'Max' not in name,
            major,
        )
        candidates.append((score, device.get('udid', '')))

if candidates:
    print(max(candidates)[1])
    sys.exit(0)

print('ERROR: No iPhone simulator found', file=sys.stderr)
sys.exit(1)
"
