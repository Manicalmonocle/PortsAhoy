#!/usr/bin/env python3
"""Pull run reports out of the Ports Ahoy inbox and decode them.

WHY THIS EXISTS. Testers send run reports by email. Copying each one out of
Gmail by hand and pasting it somewhere is the kind of chore that quietly stops
happening, and then the reports stop being read, and then there was no point
collecting them. This does the whole trip in one command:

    python3 tool/fetch_reports.py

New reports land in tool/reference_runs/incoming/ as .pa1 files and are decoded
to a readable trace beside them.

CREDENTIALS ARE NEVER IN THIS REPO AND NEVER IN A CHAT.
Make a Gmail App Password (Google Account -> Security -> 2-Step Verification
-> App passwords; the account needs 2FA on first). Then, in a terminal:

    mkdir -p ~/.config/ports_ahoy
    printf 'PORTS_AHOY_USER=portsahoy@gmail.com\\nPORTS_AHOY_APP_PASSWORD=xxxxxxxxxxxxxxxx\\n' \\
        > ~/.config/ports_ahoy/mail.env
    chmod 600 ~/.config/ports_ahoy/mail.env

That file lives outside the repository on purpose, so no commit, no build and
no push can carry it anywhere. An app password is a full-mailbox credential —
it is worth having on a dedicated account like this one and not on a personal
one, and it can be revoked from the same page that issued it.

THIS DOES NOT MODIFY YOUR MAILBOX. Nothing is marked read, moved or deleted;
already-seen messages are tracked in a local state file instead. Read your own
inbox however you like without fighting a script over it.
"""

import email
import email.policy
import email.utils
import imaplib
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "tool" / "reference_runs" / "incoming"
STATE = Path.home() / ".config" / "ports_ahoy" / "seen_messages.txt"
ENV_FILE = Path.home() / ".config" / "ports_ahoy" / "mail.env"

# A run code is one 2 KB token with no spaces in it, and mail clients wrap long
# lines — so a payload frequently arrives split across several. Rejoining it
# means deleting the whitespace inside it, which is only safe as far as the
# terminator the app appends (ReportEndpoint.mailTerminator): without that,
# a signature or the sender's own note would be glued onto the end and become
# part of the run.
#
# The unterminated form is still accepted, because reports sent before the
# terminator existed are worth reading too — those just cannot be un-wrapped.
CODE = re.compile(r"PA1~[A-Za-z0-9._~-]+")
FENCED = re.compile(r"PA1~[A-Za-z0-9._~\-\s]*?!END", re.S)


def codes_in(text):
    """Every run code in a message body, un-wrapped where it is safe to be."""
    found, spans = [], []
    for m in FENCED.finditer(text):
        # Whitespace is not in PA1's alphabet, so removing it can only rejoin
        # a code the mail client broke apart.
        code = re.sub(r"\s+", "", m.group(0)[: -len("!END")])
        if code:
            found.append(code)
            spans.append(m.span())

    # Anything outside a fenced block, for older reports.
    for m in CODE.finditer(text):
        if any(s <= m.start() < e for s, e in spans):
            continue
        found.append(m.group(0))
    return found

IMAP_HOST = "imap.gmail.com"


def load_credentials():
    user = os.environ.get("PORTS_AHOY_USER")
    password = os.environ.get("PORTS_AHOY_APP_PASSWORD")
    if user and password:
        return user, password

    if not ENV_FILE.exists():
        sys.exit(
            f"No credentials. Create {ENV_FILE} with PORTS_AHOY_USER and\n"
            f"PORTS_AHOY_APP_PASSWORD (see the comment at the top of this file),\n"
            f"or set those two environment variables."
        )

    # A world-readable password file is worth refusing over, not warning about.
    mode = ENV_FILE.stat().st_mode & 0o077
    if mode:
        sys.exit(f"{ENV_FILE} is readable by other users. Run: chmod 600 {ENV_FILE}")

    values = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()

    user = values.get("PORTS_AHOY_USER")
    password = values.get("PORTS_AHOY_APP_PASSWORD")
    if not user or not password:
        sys.exit(f"{ENV_FILE} is missing PORTS_AHOY_USER or PORTS_AHOY_APP_PASSWORD.")
    return user, password


def load_seen():
    if not STATE.exists():
        return set()
    return {line.strip() for line in STATE.read_text().splitlines() if line.strip()}


def remember(message_ids):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with STATE.open("a") as f:
        for mid in message_ids:
            f.write(mid + "\n")


def body_of(msg):
    """The plain text of a message, whatever shape the client sent it in."""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                try:
                    return part.get_content()
                except Exception:
                    continue
        # Fall back to anything at all rather than dropping the report.
        for part in msg.walk():
            if part.get_content_maintype() == "text":
                try:
                    return part.get_content()
                except Exception:
                    continue
        return ""
    try:
        return msg.get_content()
    except Exception:
        return ""


def main():
    user, password = load_credentials()
    seen = load_seen()
    OUT.mkdir(parents=True, exist_ok=True)

    try:
        conn = imaplib.IMAP4_SSL(IMAP_HOST)
        conn.login(user, password)
    except imaplib.IMAP4.error as e:
        sys.exit(
            f"Gmail refused the login: {e}\n"
            "An app password is required — a normal account password will not work,\n"
            "and the account needs 2-Step Verification enabled to issue one."
        )

    conn.select("INBOX", readonly=True)  # readonly: never mutate the mailbox
    # Search by subject rather than by sender: the sender is whoever tested.
    status, data = conn.search(None, 'SUBJECT', '"Ports Ahoy run report"')
    if status != "OK":
        sys.exit(f"IMAP search failed: {status}")

    ids = data[0].split()
    print(f"{len(ids)} message(s) in the inbox with that subject.")

    new_ids, written = [], 0
    for num in ids:
        status, raw = conn.fetch(num, "(RFC822)")
        if status != "OK" or not raw or not raw[0]:
            print(f"  could not fetch message {num!r}, skipping", file=sys.stderr)
            continue

        msg = email.message_from_bytes(raw[0][1], policy=email.policy.default)
        mid = msg.get("Message-ID", "").strip() or f"nomid-{num.decode()}"
        if mid in seen:
            continue

        codes = codes_in(body_of(msg))
        if not codes:
            print(f"  no run code in message from {msg.get('From', '?')} — skipping")
            new_ids.append(mid)  # do not re-read it forever
            continue

        when = msg.get("Date", "")
        try:
            stamp = email.utils.parsedate_to_datetime(when).astimezone(timezone.utc)
        except Exception:
            stamp = datetime.now(timezone.utc)

        for i, code in enumerate(codes):
            suffix = f"-{i + 1}" if len(codes) > 1 else ""
            name = f"{stamp:%Y-%m-%d-%H%M}{suffix}.pa1"
            path = OUT / name
            path.write_text(code + "\n")
            written += 1
            print(f"  saved {path.relative_to(REPO)}  ({len(code)} chars)")

        new_ids.append(mid)

    conn.logout()
    remember(new_ids)

    if not written:
        print("Nothing new.")
        return

    print(f"\n{written} new report(s). Decoding:\n")
    for path in sorted(OUT.glob("*.pa1")):
        txt = path.with_suffix(".txt")
        if txt.exists():
            continue
        result = subprocess.run(
            [str(Path.home() / "flutter/bin/dart"), "run",
             "tool/decode_run_report.dart", str(path)],
            cwd=REPO, capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"  {path.name}: decode failed\n{result.stderr}", file=sys.stderr)
            continue
        txt.write_text(result.stdout)
        # The header alone says whether a report is worth opening.
        for line in result.stdout.splitlines()[:10]:
            print("  " + line)
        print()


if __name__ == "__main__":
    main()
