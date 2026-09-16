#!/usr/bin/env python3
"""Classify Spark tickets as actionable.

Reads tickets JSON on stdin (list or {tickets: [...]}). HTTP/auth stay in spark.sh.

A ticket is actionable iff it is open, not a duplicate, not blockedBy a still-open
non-internal ticket, and no ancestor is. Internal tickets are ignored as blockers
and excluded from default output (--include-internal adds those that pass the rest).
"""
from __future__ import annotations

import argparse
import json
import sys

OPEN = frozenset({"new", "todo", "doing", "staging"})


def tid(obj) -> str | None:
    if isinstance(obj, dict):
        return obj.get("id") or obj.get("cuid")
    return None


def parse_tickets(raw):
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        tickets = raw.get("tickets")
        if isinstance(tickets, list):
            return tickets
    raise SystemExit("tickets-actionable: expected a ticket list or {tickets: [...]}")


def blocked_by_noninternal(ticket: dict, by_id: dict[str, dict]) -> bool:
    """True if a still-open, non-internal ticket blocks this one.

    Closed (done/rejected) and internal tickets do not count as blockers.
    Link payloads are {id,ref,title} only — status/internal come from by_id.
    """
    for b in (ticket.get("links") or {}).get("blockedBy") or []:
        bid = tid(b)
        blocker = by_id.get(bid) if bid else None
        if blocker is None:
            return True
        if blocker.get("internal"):
            continue
        if blocker.get("status") not in OPEN:
            continue
        return True
    return False


def ancestor_blocked(ticket: dict, by_id: dict[str, dict]) -> bool:
    seen: set[str] = set()
    cur = ticket
    while True:
        parent = (cur.get("links") or {}).get("parent")
        pid = tid(parent)
        if not pid or pid in seen:
            return False
        seen.add(pid)
        parent_t = by_id.get(pid)
        if parent_t is None:
            return False
        if blocked_by_noninternal(parent_t, by_id):
            return True
        cur = parent_t


def classify(tickets: list[dict]) -> dict[str, list[dict]]:
    by_id = {t["id"]: t for t in tickets if t.get("id")}
    buckets = {
        "actionable": [],
        "blocked": [],
        "parent_blocked": [],
        "internal": [],
        "closed": [],
        "duplicate": [],
    }
    for t in tickets:
        st = t.get("status")
        if st not in OPEN:
            buckets["closed"].append(t)
            continue
        if (t.get("links") or {}).get("duplicatesOf"):
            buckets["duplicate"].append(t)
            continue
        if t.get("internal"):
            buckets["internal"].append(t)
            continue
        if blocked_by_noninternal(t, by_id):
            buckets["blocked"].append(t)
            continue
        if ancestor_blocked(t, by_id):
            buckets["parent_blocked"].append(t)
            continue
        buckets["actionable"].append(t)
    pri = {"p0": 0, "p1": 1, "p2": 2, "p3": 3}
    for k, rows in buckets.items():
        buckets[k] = sorted(
            rows,
            key=lambda x: (pri.get(x.get("priority") or "p3", 9), x.get("ref") or 0),
        )
    return buckets


def row(t: dict) -> dict:
    return {
        "ref": t.get("ref"),
        "priority": t.get("priority"),
        "status": t.get("status"),
        "type": t.get("type"),
        "title": t.get("title") or "",
        "internal": bool(t.get("internal")),
    }


def pick_actionable(buckets: dict[str, list[dict]], tickets: list[dict], include_internal: bool) -> list[dict]:
    actionable = list(buckets["actionable"])
    if include_internal:
        by_id = {t["id"]: t for t in tickets if t.get("id")}
        extra = []
        for t in buckets["internal"]:
            if t.get("status") not in OPEN:
                continue
            if (t.get("links") or {}).get("duplicatesOf"):
                continue
            if blocked_by_noninternal(t, by_id) or ancestor_blocked(t, by_id):
                continue
            extra.append(t)
        actionable.extend(extra)
    return actionable


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--slug", required=True)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--include-internal", action="store_true")
    args = ap.parse_args()
    raw = json.load(sys.stdin)
    tickets = parse_tickets(raw)
    buckets = classify(tickets)
    actionable = pick_actionable(buckets, tickets, args.include_internal)
    summary = {k: len(v) for k, v in buckets.items()}
    summary["total"] = len(tickets)
    summary["actionable"] = len(actionable)
    summary["slug"] = args.slug
    if args.json:
        json.dump(
            {"summary": summary, "tickets": [row(t) for t in actionable]},
            sys.stdout,
            ensure_ascii=False,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0
    print(
        f"spark {args.slug} total={summary['total']} actionable={summary['actionable']} "
        f"blocked={summary['blocked']} parent_blocked={summary['parent_blocked']} "
        f"internal={summary['internal']} closed={summary['closed']} dup={summary['duplicate']}"
    )
    for t in actionable:
        title = (t.get("title") or "").replace("\n", " ")[:80]
        print(f"  #{t.get('ref')}\t{t.get('priority')}\t{t.get('status')}\t{title}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
