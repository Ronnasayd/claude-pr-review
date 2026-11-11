#!/usr/bin/env python3
"""Post a gate-checked the-judge review to one PR as a single GitHub review.

Usage: post_review.py findings.json --pr N --repo owner/repo
"""

# invariant: refuse to POST if review_gate.py is non-zero so a failed lint
# cannot reach GitHub.

# hazard: GitHub returns 422 on APPROVE/REQUEST_CHANGES of your own PR; fall
# back to COMMENT.

# why: CI runs as a bot token, where `gh api user` fails; the login comes from
# JUDGE_BOT_LOGIN and the PR from --pr/--repo, never from the checkout.
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

USAGE = "usage: post_review.py findings.json --pr N --repo owner/repo"
DEFAULT_LOGIN = "github-actions[bot]"
MARKER = "<!-- the-judge -->"


def run(args: list[str]) -> tuple[int, str, str]:
    """Run a command.

    Args:
        args: The command and its arguments.

    Returns:
        The exit code, stripped stdout and stripped stderr.
    """
    p = subprocess.run(args, capture_output=True, text=True, check=False)  # noqa: S603
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def gh_json(args: list[str]) -> dict:
    """Run `gh` and parse its JSON output, exiting on failure.

    Args:
        args: Arguments passed to `gh`.

    Returns:
        The parsed JSON object, or an empty dict for empty output.
    """
    rc, out, err = run(["gh", *args])
    if rc != 0:
        sys.exit(f"gh {' '.join(args)} failed: {err or out}")
    return json.loads(out) if out else {}


def flag(argv: list[str], name: str) -> str | None:
    """Return the value following `name` in argv.

    Args:
        argv: Command-line arguments.
        name: The flag to look up, such as `--pr`.

    Returns:
        The flag's value, or None when the flag or its value is missing.
    """
    if name in argv[:-1]:
        return argv[argv.index(name) + 1]
    return None


def parse_args(argv: list[str]) -> tuple[str, str, str]:
    """Read the findings path, PR number and repository, exiting with usage.

    Args:
        argv: Command-line arguments without the program name.

    Returns:
        The findings path, the PR number and the `owner/repo` string.
    """
    pr_number, repo = flag(argv, "--pr"), flag(argv, "--repo")
    if not argv or not pr_number or not repo:
        sys.exit(USAGE)
    return argv[0], pr_number, repo


def check_gate(findings_path: str) -> None:
    """Exit unless review_gate.py passes the findings file.

    Args:
        findings_path: Path to findings.json.
    """
    gate = Path(__file__).resolve().parent / "review_gate.py"
    rc, out, err = run([sys.executable, str(gate), findings_path])
    if rc != 0:
        sys.exit(f"refusing to post, gate failed:\n{out}{err}")


def build_payload(data: dict, author: str) -> dict:
    """Build the review payload, downgrading the verdict on the bot's own PR.

    Args:
        data: The parsed findings.json.
        author: Login of the PR author.

    Returns:
        The payload with body, event and inline comments.
    """
    verdict = data["verdict"]
    body = data["summary"]
    me = os.environ.get("JUDGE_BOT_LOGIN") or DEFAULT_LOGIN
    event = verdict
    if me == author and verdict != "COMMENT":
        event = "COMMENT"
        body = (
            f"{body}\n\n---\n_Intended verdict: **{verdict}**. "
            f"Posted as a comment because GitHub does not allow {verdict} "
            "on the author's own PR._"
        )
    comments = [
        {"path": f["path"], "line": f["line"], "side": "RIGHT", "body": f["body"]}
        for f in data["findings"]
        if f.get("severity") != "pre-existing" and f.get("line")
    ]
    return {"body": f"{body}\n\n{MARKER}", "event": event, "comments": comments}


def submit(repo: str, number: int, payload: dict) -> tuple[int, str, str]:
    """POST one review.

    Args:
        repo: The `owner/repo` string.
        number: The PR number.
        payload: The review payload.

    Returns:
        The exit code, stdout and stderr of `gh api`.
    """
    with tempfile.NamedTemporaryFile(
        "w", suffix=".json", delete=False, encoding="utf-8"
    ) as tmp:
        json.dump(payload, tmp, ensure_ascii=False)
        tmp_path = tmp.name
    try:
        return run(
            [
                "gh",
                "api",
                f"repos/{repo}/pulls/{number}/reviews",
                "--method",
                "POST",
                "--input",
                tmp_path,
            ]
        )
    finally:
        Path(tmp_path).unlink()


def main() -> None:
    """Gate the findings file, then post it as one review."""
    findings_path, pr_number, repo = parse_args(sys.argv[1:])
    check_gate(findings_path)
    data = json.loads(Path(findings_path).read_text(encoding="utf-8"))
    pr = gh_json(["pr", "view", pr_number, "--repo", repo, "--json", "number,author"])
    payload = build_payload(data, pr["author"]["login"])
    comments = payload["comments"]

    rc, out, err = submit(repo, pr["number"], payload)
    if rc != 0:
        msg = err or out
        if "422" in msg and comments:
            anchors = ", ".join(f"{c['path']}:{c['line']}" for c in comments)
            msg += (
                "\nhint: HTTP 422 with inline comments usually means an anchor "
                f"line is not part of the diff. Anchors sent: {anchors}. "
                "Re-anchor on a changed line from the patch or fold the finding "
                "into the summary."
            )
        sys.exit(f"review submission failed: {msg}")

    url = json.loads(out).get("html_url", "(no url returned)")
    print(  # noqa: T201
        f"posted: event={payload['event']} comments={len(comments)} url={url}"
    )


if __name__ == "__main__":
    main()
