#!/bin/bash
# Script to ensure ProjectLinterTests.swift is only included in the SwiftProjectLintCoreTests target
# and not in the SwiftProjectLintCore framework target.

set -euo pipefail

PROJECT_FILE="SwiftProjectLint.xcodeproj/project.pbxproj"
TEST_FILE="SwiftProjectLintCore/SwiftProjectLintCoreTests/ProjectLinterTests.swift"
CORE_TARGET="SwiftProjectLintCore"
TEST_TARGET="SwiftProjectLintCoreTests"

if [ ! -f "$PROJECT_FILE" ]; then
  echo "Error: $PROJECT_FILE not found. Run this script from the project root."
  exit 1
fi

# Find the file reference for ProjectLinterTests.swift
FILE_REF=$(grep -B2 "$TEST_FILE" "$PROJECT_FILE" | grep 'fileRef' | awk '{print $3}' | sed 's/;//')
if [ -z "$FILE_REF" ]; then
  echo "Error: Could not find file reference for $TEST_FILE in $PROJECT_FILE."
  exit 1
fi

echo "Found file reference: $FILE_REF for $TEST_FILE"

# Remove from SwiftProjectLintCore target's sources build phase
CORE_BUILD_PHASE=$(grep -B4 "$CORE_TARGET" "$PROJECT_FILE" | grep 'SourcesBuildPhase' | awk '{print $1}' | sed 's/://')
if [ -n "$CORE_BUILD_PHASE" ]; then
  if grep -q "$FILE_REF" "$PROJECT_FILE"; then
    echo "Removing $TEST_FILE from $CORE_TARGET sources build phase ($CORE_BUILD_PHASE)"
    sed -i '' "/$CORE_BUILD_PHASE/,/);/s/\s*$FILE_REF,\?//" "$PROJECT_FILE"
  fi
fi

# Ensure it is in the test target (optional, as Xcode usually manages this)
echo "Done. Please verify in Xcode that $TEST_FILE is only in $TEST_TARGET target." 