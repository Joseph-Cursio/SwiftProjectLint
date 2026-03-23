#!/bin/bash

set -e

PROJECT_FILE="SwiftProjectLint.xcodeproj/project.pbxproj"

# Backup
cp "$PROJECT_FILE" "$PROJECT_FILE.bak"

add_files_to_target() {
  TEST_DIR="$1"
  TARGET_NAME="$2"
  SOURCES_PHASE_ID="$3"

  echo "Patching $TARGET_NAME..."

  for file in "$TEST_DIR"/*.swift; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    fileref_id=$(uuidgen | tr -d '-' | cut -c1-24)
    buildfile_id=$(uuidgen | tr -d '-' | cut -c1-24)

    # Check if file is already present
        if grep -q "$filename" "$PROJECT_FILE"; then
      echo "  $filename already present, skipping."
      continue
    fi

    # Add PBXFileReference
    sed -i '' "/\/\* End PBXFileReference section \*\//i\\
        \t\t$fileref_id /* $filename */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"$filename\"; sourceTree = \"<group>\"; };
    " "$PROJECT_FILE"

    # Add PBXBuildFile
    sed -i '' "/\/\* End PBXBuildFile section \*\//i\\
        \t\t$buildfile_id /* $filename in Sources */ = {isa = PBXBuildFile; fileRef = $fileref_id /* $filename */; };
    " "$PROJECT_FILE"

    # Add to PBXSourcesBuildPhase
    # Find the files = ( ... ); block for the target's Sources phase
    awk -v id="$SOURCES_PHASE_ID" -v buildfile="$buildfile_id" -v filename="$filename" '
      BEGIN {in_phase=0}
      {
        if ($0 ~ id " /\\* Sources \\*/ =") in_phase=1
        if (in_phase && $0 ~ /files = \(/) {
          print $0
          print "\t\t\t\t" buildfile " /* " filename " in Sources */,";
          in_phase=0
          next
        }
        print $0
      }
    ' "$PROJECT_FILE" > "$PROJECT_FILE.tmp" && mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"

    echo "  Added $filename"
  done
}

# You must set the correct PBXSourcesBuildPhase IDs for your test targets.
# Find these in your project.pbxproj (look for PBXSourcesBuildPhase for each test target).
# Example IDs (replace with your actual IDs if different):
#   AppTests:    2805B49A2E149DAC0018C12A
#   CoreTests:28B7966A2E19EDA400AE3C7B

add_files_to_target "AppTests" "AppTests" "2805B49A2E149DAC0018C12A"
add_files_to_target "CoreTests" "CoreTests" "28B7966A2E19EDA400AE3C7B"

echo "Done. Please open Xcode and verify the test files are now included in the test targets."