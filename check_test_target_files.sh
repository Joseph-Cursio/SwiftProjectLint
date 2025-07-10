#!/bin/bash

PROJECT_FILE="SwiftProjectLint.xcodeproj/project.pbxproj"

check_target() {
  TEST_DIR="$1"
  TARGET_NAME="$2"

  echo "Checking $TARGET_NAME..."

  # List all .swift files in the test directory
  find "$TEST_DIR" -name '*.swift' -print | while read -r file; do
    # Get the filename only
    filename=$(basename "$file")
    # Check if the file is referenced in the project.pbxproj
    if ! grep -q "$filename" "$PROJECT_FILE"; then
      echo "  MISSING from $TARGET_NAME: $filename"
    fi
  done
}

check_target "SwiftProjectLintTests" "SwiftProjectLintTests"
check_target "SwiftProjectLintCoreTests" "SwiftProjectLintCoreTests"