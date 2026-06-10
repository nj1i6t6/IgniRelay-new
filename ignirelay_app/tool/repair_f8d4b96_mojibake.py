# One-shot repair for the f8d4b96 mojibake (task A0).
#
# f8d4b96 re-saved five test files through a lossy encoding, replacing
# non-ASCII characters (CJK strings, em-dashes, arrows) with '?'. This script
# restores ONLY lines whose ASCII residue matches the fork-point (30eed86)
# version exactly — i.e. lines where the sole difference is corrupted
# non-ASCII. Real 4-3 edits (fieldId args, pv=3 expectations) are untouched.
#
# Usage: python tool/repair_f8d4b96_mojibake.py        (run from ignirelay_app/)
# Idempotent: a second run reports 0 restorations.

import difflib
import subprocess
import sys
from pathlib import Path

FORK = "30eed86"
FILES = [
    "ignirelay_app/test/controllers/envelope_pipeline_v2_test.dart",
    "ignirelay_app/test/crypto/canonical_encoder_v2_test.dart",
    "ignirelay_app/test/services/ble_v2_bridge_test.dart",
    "ignirelay_app/test/services/protocol_hello_test.dart",
    "ignirelay_app/test/services/v2_inbound_projector_test.dart",
]


def ascii_residue(line: str) -> str:
    # Drop '?'/whitespace and every non-ASCII char; what remains must match
    # for a line to be considered "corruption-only". Whitespace is dropped
    # because the mangler also swallowed the space following an em-dash.
    return "".join(
        c for c in line if ord(c) < 128 and c != "?" and not c.isspace()
    )


def is_corrupted_variant(cur: str, fork: str) -> bool:
    if cur == fork:
        return False
    if "?" not in cur:
        return False
    if not any(ord(c) > 127 for c in fork):
        return False
    return ascii_residue(cur) == ascii_residue(fork)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    total = 0
    for rel in FILES:
        fork_text = subprocess.run(
            ["git", "show", f"{FORK}:{rel}"],
            capture_output=True, cwd=repo_root, check=True,
        ).stdout.decode("utf-8")
        path = repo_root / rel
        cur_text = path.read_text(encoding="utf-8")
        fork_lines = fork_text.splitlines(keepends=True)
        cur_lines = cur_text.splitlines(keepends=True)

        sm = difflib.SequenceMatcher(a=fork_lines, b=cur_lines, autojunk=False)
        restored = 0
        out = list(cur_lines)
        for tag, a0, a1, b0, b1 in sm.get_opcodes():
            if tag != "replace":
                continue
            fork_block = fork_lines[a0:a1]
            for bi in range(b0, b1):
                cur_line = cur_lines[bi]
                matches = [fl for fl in fork_block
                           if is_corrupted_variant(cur_line, fl)]
                if len(matches) == 1:
                    out[bi] = matches[0]
                    restored += 1
                elif len(matches) > 1:
                    print(f"AMBIGUOUS {rel}:{bi + 1} — manual review", file=sys.stderr)
        if restored:
            path.write_text("".join(out), encoding="utf-8", newline="")
        leftover = sum(1 for ln in out if "?" in ln and "??" in ln)
        print(f"{rel}: restored={restored} suspicious-??-lines-left={leftover}")
        total += restored
    print(f"TOTAL restored lines: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
