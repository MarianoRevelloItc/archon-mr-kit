#!/usr/bin/env bash
# Static validator for archon-mr-kit artifacts.
#
# Checks (all offline — no archon CLI, no Anthropic API):
#   1. Every YAML in .archon/workflows/ parses and has required top-level keys.
#   2. Every MD in .archon/commands/ has parseable YAML frontmatter.
#   3. For each command with `requires_skills: [...]`, those skills exist in .claude/skills/<name>/SKILL.md.
#   4. For each workflow node `skills: [...]`, those skills exist.
#   5. Wiring: for each command C with `requires_skills: [X]`, every workflow node that calls C
#      either lists X in `skills:` or grep-references X in C's body.
#
# Exit 0 on success, 1 on any failure.
#
# Usage:
#   bash scripts/test-bootstrap.sh
#
# Used by:
#   - .archon/commands/mr-kit-validate.md
#   - .github/workflows/template-smoke.yml
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Make sure pyyaml is available; install only if missing (CI may install before us).
python3 -c "import yaml" 2>/dev/null || python3 -m pip install --quiet pyyaml

python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

import yaml

REPO = Path(os.getcwd())
WORKFLOWS = REPO / ".archon" / "workflows"
COMMANDS = REPO / ".archon" / "commands"
SKILLS = REPO / ".claude" / "skills"

failures = []
checked = 0


def fail(artifact: str, reason: str) -> None:
    failures.append((artifact, reason))


def ok(label: str) -> None:
    print(f"  {label} OK")


def parse_frontmatter(text: str):
    """Return (frontmatter_dict, body_str). frontmatter_dict is {} if no FM block."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end < 0:
        raise ValueError("frontmatter opened with --- but never closed with ---")
    fm_raw = text[4:end]
    body = text[end + 4 :].lstrip("\n")
    data = yaml.safe_load(fm_raw) or {}
    if not isinstance(data, dict):
        raise ValueError("frontmatter is not a YAML mapping")
    return data, body


def list_skills() -> set:
    if not SKILLS.is_dir():
        return set()
    found = set()
    for entry in SKILLS.iterdir():
        if entry.is_dir() and (entry / "SKILL.md").is_file():
            found.add(entry.name)
        # _optional/ holds skills that bootstrap may copy on demand — index those too,
        # but namespaced so they don't collide with default-loaded skills.
    optional = SKILLS / "_optional"
    if optional.is_dir():
        for entry in optional.iterdir():
            if entry.is_dir() and (entry / "SKILL.md").is_file():
                found.add(f"_optional/{entry.name}")
    return found


print("== archon-mr-kit static validator ==")

# 1. Workflows --------------------------------------------------------------
print("[workflows]")
workflow_data: dict[str, dict] = {}
if not WORKFLOWS.is_dir():
    fail(".archon/workflows", "directory missing")
else:
    for path in sorted(WORKFLOWS.glob("*.yaml")):
        checked += 1
        rel = path.relative_to(REPO)
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(str(rel), f"YAML parse error: {exc}")
            print(f"  {rel} FAIL")
            continue
        if not isinstance(data, dict):
            fail(str(rel), "top-level YAML is not a mapping")
            print(f"  {rel} FAIL")
            continue
        for key in ("name", "nodes"):
            if key not in data:
                fail(str(rel), f"missing top-level key '{key}'")
        nodes = data.get("nodes")
        if nodes is not None and not isinstance(nodes, list):
            fail(str(rel), "'nodes' must be a list")
        workflow_data[path.stem] = data
        print(f"  {rel} OK")

# 2. Commands --------------------------------------------------------------
print("[commands]")
command_data: dict[str, dict] = {}  # name → {requires_skills, body}
if not COMMANDS.is_dir():
    fail(".archon/commands", "directory missing")
else:
    for path in sorted(COMMANDS.glob("*.md")):
        checked += 1
        rel = path.relative_to(REPO)
        try:
            fm, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(str(rel), f"frontmatter parse error: {exc}")
            print(f"  {rel} FAIL")
            continue
        if "description" not in fm:
            fail(str(rel), "frontmatter missing 'description'")
        requires = fm.get("requires_skills", [])
        if requires and not isinstance(requires, list):
            fail(str(rel), "'requires_skills' must be a list")
            requires = []
        command_data[path.stem] = {
            "requires_skills": list(requires) if isinstance(requires, list) else [],
            "body": body,
        }
        suffix = f" (requires: {','.join(requires)})" if requires else ""
        print(f"  {rel}{suffix} OK")

# 3. Skills --------------------------------------------------------------
# Each skill must have a SKILL.md with frontmatter declaring `name:` and `description:`
# (Anthropic's Claude Code skill convention — without these, autoload won't trigger).
print("[skills]")
skills_present = list_skills()
for name in sorted(skills_present):
    checked += 1
    skill_md = SKILLS / name / "SKILL.md"
    if "/" in name:  # _optional/<n>
        skill_md = SKILLS / name / "SKILL.md"
    try:
        fm, _ = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f".claude/skills/{name}/SKILL.md", f"frontmatter parse error: {exc}")
        print(f"  .claude/skills/{name} FAIL")
        continue
    missing = [k for k in ("name", "description") if k not in fm]
    if missing:
        fail(
            f".claude/skills/{name}/SKILL.md",
            f"frontmatter missing keys: {', '.join(missing)}",
        )
        print(f"  .claude/skills/{name} FAIL")
        continue
    print(f"  .claude/skills/{name} OK")

# 4. requires_skills exist --------------------------------------------------
for cmd_name, info in command_data.items():
    for req in info["requires_skills"]:
        if req not in skills_present:
            fail(
                f".archon/commands/{cmd_name}.md",
                f"requires_skills '{req}' not found in .claude/skills/",
            )

# 5. Workflow node skills exist + wiring ----------------------------------
print("[wiring]")
for wf_name, data in workflow_data.items():
    nodes = data.get("nodes") or []
    for node in nodes:
        if not isinstance(node, dict):
            continue
        node_id = node.get("id", "<unnamed>")
        node_skills = node.get("skills") or []
        if node_skills and not isinstance(node_skills, list):
            fail(f".archon/workflows/{wf_name}.yaml", f"node '{node_id}': 'skills' must be a list")
            continue
        # 5a. Each declared skill must exist
        for s in node_skills:
            if s not in skills_present:
                fail(
                    f".archon/workflows/{wf_name}.yaml",
                    f"node '{node_id}' references skill '{s}' that doesn't exist",
                )
        # 5b. If the node calls a command that requires_skills, check wiring
        cmd_called = node.get("command")
        if cmd_called and cmd_called in command_data:
            for req in command_data[cmd_called]["requires_skills"]:
                if req in node_skills:
                    print(
                        f"  {wf_name}.{node_id} → {cmd_called} (requires: {req}) — node has skills:[{req}] OK"
                    )
                elif re.search(rf"\b{re.escape(req)}\b", command_data[cmd_called]["body"]):
                    print(
                        f"  {wf_name}.{node_id} → {cmd_called} (requires: {req}) — body grep matches OK"
                    )
                else:
                    fail(
                        f".archon/workflows/{wf_name}.yaml",
                        f"node '{node_id}' calls '{cmd_called}' which requires skill '{req}', "
                        f"but node has no skills:[{req}] and command body never references it",
                    )

# Report ------------------------------------------------------------------
print()
if failures:
    print(f"== FAIL ({checked} artifacts checked, {len(failures)} failures) ==")
    for art, reason in failures:
        print(f"  - {art}: {reason}")
    sys.exit(1)
else:
    print(f"== PASS ({checked} artifacts checked, 0 failures) ==")
    sys.exit(0)
PY
