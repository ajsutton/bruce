#!/usr/bin/env python3
"""Exercise the workflow's prerelease creation without touching GitHub."""

import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
workflow = (root / ".github/workflows/release-rc.yml").read_text()
step = workflow.split("      - name: Create prerelease for main push\n", 1)[1]
step = step.split("\n      - name:", 1)[0]
script = "\n".join(line[10:] for line in step.split("        run: |\n", 1)[1].splitlines())

with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    (fixture / "scripts/lib").mkdir(parents=True)
    (fixture / "scripts/lib/release-common.sh").write_text(
        (root / "scripts/lib/release-common.sh").read_text()
    )
    (fixture / "bin").mkdir()
    (fixture / "bin/gh").write_text(
        '#!/bin/bash\nprintf "%s\\n" "$@" > "$CALL_LOG"\nexit "${GH_EXIT:-0}"\n'
    )
    (fixture / "bin/git").write_text('#!/bin/bash\nprintf "%s\\n" "$TEST_TAGS"\n')
    for tool in (fixture / "bin").iterdir():
        tool.chmod(0o755)
    env = dict(
        os.environ,
        PATH=str(fixture / "bin") + ":" + os.environ["PATH"],
        COMMIT_SHA="a" * 40,
        GITHUB_RUN_ID="12345",
        GITHUB_RUN_ATTEMPT="2",
        GITHUB_OUTPUT=str(fixture / "output"),
        GITHUB_STEP_SUMMARY=str(fixture / "summary"),
        CALL_LOG=str(fixture / "call"),
    )
    command = ["bash", "-e", "-o", "pipefail", "-c", script]
    cases = [
        ("", "v1.2.0-rc.1", None),
        ("v1.2.0-rc.2\nv1.2.0-rc.10", "v1.2.0-rc.11", "v1.2.0-rc.10"),
        ("v1.1.0", "v1.2.0-rc.1", "v1.1.0"),
    ]
    for tags, expected, base in cases:
        (fixture / "project.yml").write_text('  MARKETING_VERSION: "1.2.0"\n')
        (fixture / "output").write_text("")
        env["TEST_TAGS"] = tags
        subprocess.run(command, cwd=fixture, env=env, check=True)
        args = (fixture / "call").read_text().splitlines()
        assert args[:3] == ["release", "create", expected], args
        assert args[args.index("--target") + 1] == env["COMMIT_SHA"]
        assert "--prerelease" in args and "--generate-notes" in args
        assert args[args.index("--notes") + 1] == "<!-- bruce-release-run:12345:2 -->"
        if base:
            assert args[args.index("--notes-start-tag") + 1] == base
        else:
            assert "--notes-start-tag" not in args
        assert (fixture / "output").read_text() == f"tag={expected}\n"
        print(f"PASS automatic prerelease {expected}, notes base: {base}")

    (fixture / "call").unlink()
    (fixture / "project.yml").write_text('  MARKETING_VERSION: "invalid"\n')
    result = subprocess.run(command, cwd=fixture, env=env, capture_output=True)
    assert result.returncode and not (fixture / "call").exists()
    print("PASS invalid version cannot create a release")

    (fixture / "project.yml").write_text('  MARKETING_VERSION: "1.2.0"\n')
    (fixture / "output").write_text("")
    env["GH_EXIT"] = "1"
    result = subprocess.run(command, cwd=fixture, env=env, capture_output=True)
    assert result.returncode and not (fixture / "output").read_text()
    print("PASS failed release creation cannot continue to upload")
