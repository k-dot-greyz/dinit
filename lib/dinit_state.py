#!/usr/bin/env python3
"""dinit phase catalog and state algebra."""

from __future__ import annotations

import fcntl
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

CATALOG_PATH = Path(__file__).with_name("phases.json")
SCHEMA = "dinit.state.v1"
DONE = {"ok", "skipped"}
TERMINAL_FAIL = {"blocked", "failed"}


def load_catalog(path: Path | None = None) -> dict:
    catalog_path = path or CATALOG_PATH
    with catalog_path.open() as f:
        catalog = json.load(f)
    if not catalog.get("phases"):
        raise ValueError("catalog has no phases")
    return catalog


def phase_list(catalog: dict | None = None) -> list[dict]:
    catalog = catalog or load_catalog()
    return list(catalog["phases"])


def phase_ids(catalog: dict | None = None) -> list[str]:
    return [p["id"] for p in phase_list(catalog)]


def phase_card(phase: str, catalog: dict | None = None) -> dict:
    for card in phase_list(catalog):
        if card["id"] == phase:
            return card
    raise KeyError(f"unknown phase: {phase}")


def phase_kind(phase: str, catalog: dict | None = None) -> str:
    return str(phase_card(phase, catalog)["kind"])


def phase_skippable(phase: str, catalog: dict | None = None) -> bool:
    return bool(phase_card(phase, catalog).get("skippable"))


def phase_apply(phase: str, catalog: dict | None = None) -> str:
    return str(phase_card(phase, catalog)["apply"])


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def counts_for_complete(card: dict) -> bool:
    return card.get("kind") != "session"


def compute_complete(phases: dict, catalog: dict | None = None) -> bool:
    for card in phase_list(catalog):
        if not counts_for_complete(card):
            continue
        if phases.get(card["id"], "pending") not in DONE:
            return False
    return True


def first_pending(phases: dict, catalog: dict | None = None) -> str:
    for card in phase_list(catalog):
        if not counts_for_complete(card):
            continue
        if phases.get(card["id"], "pending") not in DONE:
            return card["id"]
    return ""


def initial_state(catalog: dict | None = None) -> dict:
    ids = phase_ids(catalog)
    return {
        "schema": SCHEMA,
        "updated_at": now_stamp(),
        "complete": False,
        "seeded": False,
        "phases": {phase: "pending" for phase in ids},
        "blocker": None,
    }


def apply_status(
    state: dict,
    phase: str,
    status: str,
    msg: str = "",
    nxt: str = "dinit",
    catalog: dict | None = None,
) -> dict:
    phase_card(phase, catalog)  # validate
    state.setdefault("phases", {})[phase] = status
    state["updated_at"] = now_stamp()
    blocker = state.get("blocker") or {}
    if status == "ok":
        state["blocker"] = None
    elif status in TERMINAL_FAIL and msg:
        state["blocker"] = {"phase": phase, "message": msg, "next": nxt or "dinit"}
    elif status in ("skipped", "pending") and blocker.get("phase") == phase:
        state["blocker"] = None
    state["complete"] = compute_complete(state.get("phases", {}), catalog)
    return state


def skip_phase(
    state: dict,
    phase: str,
    msg: str = "",
    nxt: str = "dinit",
    catalog: dict | None = None,
) -> dict:
    if not phase_skippable(phase, catalog):
        raise PermissionError(f"phase {phase} is not skippable")
    return apply_status(state, phase, "skipped", msg, nxt, catalog)


def reset_phase(state: dict, phase: str, catalog: dict | None = None) -> dict:
    return apply_status(state, phase, "pending", "", "dinit", catalog)


class StateStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.lock_path = self.path.with_name(self.path.name + ".lock")

    def _lock(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lock = self.lock_path.open("a+")
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        return lock

    def load(self) -> dict:
        if not self.path.is_file():
            return initial_state()
        with self.path.open() as f:
            return json.load(f)

    def save(self, state: dict) -> None:
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        with tmp.open("w") as f:
            json.dump(state, f, indent=2)
            f.write("\n")
        tmp.replace(self.path)

    def mutate(self, fn):
        lock = self._lock()
        try:
            state = self.load()
            state = fn(state)
            self.save(state)
            return state
        finally:
            lock.close()


def cmd_init(path: str) -> None:
    store = StateStore(path)
    lock = store._lock()
    try:
        if not store.path.is_file():
            store.save(initial_state())
    finally:
        lock.close()


def cmd_get(path: str, phase: str) -> None:
    phases = StateStore(path).load().get("phases", {})
    print(phases.get(phase, "pending"))


def cmd_set(path: str, phase: str, status: str, msg: str = "", nxt: str = "dinit") -> None:
    def mut(state):
        return apply_status(state, phase, status, msg, nxt)

    StateStore(path).mutate(mut)


def cmd_first_pending(path: str) -> None:
    state = StateStore(path).load()
    print(first_pending(state.get("phases", {})))


def cmd_is_complete(path: str) -> None:
    state = StateStore(path).load()
    print("true" if compute_complete(state.get("phases", {})) else "false")


def cmd_blocker(path: str) -> None:
    blocker = StateStore(path).load().get("blocker")
    print(json.dumps(blocker) if blocker else "")


def cmd_skip(path: str, phase: str, msg: str = "", nxt: str = "dinit") -> None:
    def mut(state):
        return skip_phase(state, phase, msg, nxt)

    try:
        StateStore(path).mutate(mut)
    except PermissionError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


def cmd_reset(path: str, phase: str) -> None:
    def mut(state):
        return reset_phase(state, phase)

    StateStore(path).mutate(mut)


def cmd_kind(phase: str) -> None:
    print(phase_kind(phase))


def cmd_skippable(phase: str) -> None:
    print("true" if phase_skippable(phase) else "false")


def cmd_apply(phase: str) -> None:
    print(phase_apply(phase))


def cmd_ids() -> None:
    print("\n".join(phase_ids()))


def cmd_table(path: str) -> None:
    state = StateStore(path).load()
    phases = state.get("phases", {})
    for card in phase_list():
        status = phases.get(card["id"], "pending")
        print(f"{card['id']}\t{card['kind']}\t{status}\t{card.get('retry', 'none')}")


def cmd_dump(path: str) -> None:
    print(json.dumps(StateStore(path).load(), separators=(",", ":")))


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print("dinit_state.py: missing command", file=sys.stderr)
        return 2
    cmd = argv[0]
    args = argv[1:]
    try:
        if cmd == "init":
            cmd_init(args[0])
        elif cmd == "get":
            cmd_get(args[0], args[1])
        elif cmd == "set":
            msg = args[3] if len(args) > 3 else ""
            nxt = args[4] if len(args) > 4 else "dinit"
            cmd_set(args[0], args[1], args[2], msg, nxt)
        elif cmd == "first-pending":
            cmd_first_pending(args[0])
        elif cmd == "is-complete":
            cmd_is_complete(args[0])
        elif cmd == "blocker":
            cmd_blocker(args[0])
        elif cmd == "skip":
            msg = args[2] if len(args) > 2 else ""
            nxt = args[3] if len(args) > 3 else "dinit"
            cmd_skip(args[0], args[1], msg, nxt)
        elif cmd == "reset":
            cmd_reset(args[0], args[1])
        elif cmd == "kind":
            cmd_kind(args[0])
        elif cmd == "skippable":
            cmd_skippable(args[0])
        elif cmd == "apply":
            cmd_apply(args[0])
        elif cmd == "ids":
            cmd_ids()
        elif cmd == "table":
            cmd_table(args[0])
        elif cmd == "dump":
            cmd_dump(args[0])
        else:
            print(f"unknown command: {cmd}", file=sys.stderr)
            return 2
    except KeyError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
