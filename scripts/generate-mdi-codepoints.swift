#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("Usage: generate-mdi-codepoints.swift <materialdesignicons.css> <output.json>\n".utf8)
  )
  exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let pattern = #"\.mdi-([a-z0-9-]+)::before\s*\{\s*content:\s*"\\([A-F0-9]+)";"#
let expression = try NSRegularExpression(pattern: pattern)
let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
var codepoints: [String: UInt32] = [:]

for match in expression.matches(in: source, range: sourceRange) {
  guard
    let nameRange = Range(match.range(at: 1), in: source),
    let codepointRange = Range(match.range(at: 2), in: source),
    let codepoint = UInt32(source[codepointRange], radix: 16)
  else {
    continue
  }
  codepoints[String(source[nameRange])] = codepoint
}

guard !codepoints.isEmpty else {
  FileHandle.standardError.write(Data("No MDI codepoints found.\n".utf8))
  exit(1)
}

let data = try JSONSerialization.data(
  withJSONObject: codepoints,
  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try FileManager.default.createDirectory(
  at: destinationURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)
try data.write(to: destinationURL)
print("Wrote \(codepoints.count) MDI codepoints.")
