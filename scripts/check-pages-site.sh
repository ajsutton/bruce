#!/usr/bin/env bash
set -euo pipefail

site_root="docs"
domain="bruce.symphonious.net"
application_identifier="P8LX6DFJM4.net.symphonious.bruce"

required_files=(
  "$site_root/.nojekyll"
  "$site_root/CNAME"
  "$site_root/index.html"
  "$site_root/auth/index.html"
  "$site_root/.well-known/apple-app-site-association"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Pages file: $required_file"
    exit 1
  fi
done

if [[ "$(tr -d '\r\n' < "$site_root/CNAME")" != "$domain" ]]; then
  echo "docs/CNAME must contain only $domain"
  exit 1
fi

for page in "$site_root/index.html" "$site_root/auth/index.html"; do
  grep -q '<html lang="en-AU">' "$page"
  grep -q 'name="viewport"' "$page"
  grep -q 'name="description"' "$page"
  grep -Eq '<title>[^<]+</title>' "$page"

  if grep -Eiq '<script|<form|https?://|analytics|cookie' "$page"; then
    echo "$page contains a prohibited active or remote dependency"
    exit 1
  fi
done

association_file="$site_root/.well-known/apple-app-site-association"
normalized_association="$(plutil -convert json -o - "$association_file")"
expected_association="{\"webcredentials\":{\"apps\":[\"$application_identifier\"]}}"
if [[ "$normalized_association" != "$expected_association" ]]; then
  echo "Apple association file must contain only the expected web credentials application"
  exit 1
fi

echo "GitHub Pages site checks passed."
