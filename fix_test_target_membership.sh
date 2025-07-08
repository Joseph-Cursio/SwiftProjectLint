#!/bin/bash
# Ensures ProjectLinterTests.swift is only in the SwiftProjectLintCoreTests target
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
FILE_REF=$(grep -B2 "$TEST_FILE" "$PROJECT_FILE" | grep fileRef | awk '{print $3}' | sed 's/;//')
if [ -z "$FILE_REF" ]; then
  echo "File reference for $TEST_FILE not found in project file."
  echo "You may need to add the file to the test target manually in Xcode."
  exit 1
fi

echo "Found fileRef: $FILE_REF for $TEST_FILE"

# Remove from SwiftProjectLintCore sources build phase
CORE_BUILD_PHASE=$(grep -B2 "name = $CORE_TARGET" "$PROJECT_FILE" | grep -B1 "isa = PBXSourcesBuildPhase" | head -1 | awk '{print $1}' | sed 's/://')
if [ -n "$CORE_BUILD_PHASE" ]; then
  if grep -A20 "$CORE_BUILD_PHASE" "$PROJECT_FILE" | grep -q "$FILE_REF"; then
    echo "Removing $TEST_FILE from $CORE_TARGET sources build phase."
    sed -i.bak "/$CORE_BUILD_PHASE/,/);/s/\s*$FILE_REF,\?//" "$PROJECT_FILE"
  else
    echo "$TEST_FILE not found in $CORE_TARGET sources build phase."
  fi
else
  echo "Could not find sources build phase for $CORE_TARGET."
fi

echo "Done. Please verify in Xcode that $TEST_FILE is only included in $TEST_TARGET target." 