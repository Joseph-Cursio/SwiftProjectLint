#!/usr/bin/env python3
"""
Check for drift between RuleIdentifier cases and Docs/rules/*.md pages.

Each rule doc declares its user-facing identifier in a markdown line of
the form:

    **Identifier:** `Some Rule Name`

That backticked name should match the `rawValue` of one (and only one)
case in `RuleIdentifier.swift`. This script verifies the mapping is
exhaustive and bijective. The doc *filename* is intentionally not
checked — the project deliberately splits SwiftUI compound type names
(`ForEach` → `for-each`) and keeps brand names (`SwiftData`, `CloudKit`)
together in filenames; the canonical link between rule and doc is the
declared Identifier, not the filename.

Exits 0 on clean, 1 on any drift, 2 on infrastructure errors.

Usage:
    tools/check-doc-drift.py
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RULE_IDENTIFIER_PATH = REPO_ROOT / "Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift"
DOCS_DIR = REPO_ROOT / "Docs/rules"

# Doc files that aren't rule pages (no Identifier: declaration expected).
NON_RULE_DOCS = {"RULES.md"}


def extract_rule_raw_values(source: str) -> dict[str, str]:
    """Return {rawValue: caseName} from RuleIdentifier.swift."""
    pattern = re.compile(r'^    case ([a-z][A-Za-z0-9]+)\s*=\s*"([^"]+)"', re.M)
    out: dict[str, str] = {}
    for case_name, raw_value in pattern.findall(source):
        if raw_value in out:
            print(f"warning: duplicate rawValue {raw_value!r} on cases "
                  f"{out[raw_value]!r} and {case_name!r}", file=sys.stderr)
        out[raw_value] = case_name
    return out


def extract_doc_identifiers(docs_dir: Path) -> dict[str, str]:
    """Return {declaredIdentifier: filename} for every rule doc."""
    pattern = re.compile(r'^\*\*Identifier:\*\*\s*`([^`]+)`', re.M)
    out: dict[str, str] = {}
    for path in sorted(docs_dir.glob("*.md")):
        if path.name in NON_RULE_DOCS:
            continue
        match = pattern.search(path.read_text())
        if not match:
            print(f"warning: {path.name} has no `**Identifier:**` line",
                  file=sys.stderr)
            continue
        declared = match.group(1)
        if declared in out:
            print(f"warning: identifier {declared!r} declared in both "
                  f"{out[declared]!r} and {path.name!r}", file=sys.stderr)
        out[declared] = path.name
    return out


def main() -> int:
    if not RULE_IDENTIFIER_PATH.exists():
        print(f"error: {RULE_IDENTIFIER_PATH} not found", file=sys.stderr)
        return 2
    if not DOCS_DIR.exists():
        print(f"error: {DOCS_DIR} not found", file=sys.stderr)
        return 2

    rules = extract_rule_raw_values(RULE_IDENTIFIER_PATH.read_text())
    docs = extract_doc_identifiers(DOCS_DIR)

    rule_ids, doc_ids = set(rules), set(docs)
    missing_doc = sorted(rule_ids - doc_ids)
    orphan_doc = sorted(doc_ids - rule_ids)

    print(f"rules: {len(rules)}  docs: {len(docs)}")

    if not missing_doc and not orphan_doc:
        print("OK — every rule has a doc and every doc maps to a rule")
        return 0

    if missing_doc:
        print("\nrules with no doc (no `**Identifier:** \\`<rawValue>\\`` "
              "declaration found):")
        for raw in missing_doc:
            print(f"  {raw!r}  (case: {rules[raw]})")

    if orphan_doc:
        print("\ndocs with no matching rule (declared identifier doesn't "
              "match any RuleIdentifier rawValue):")
        for raw in orphan_doc:
            print(f"  {docs[raw]}  declares: {raw!r}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
