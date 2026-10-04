"""Nudge -- command-line surface.

Every command is a bridged, awaited call into core.api -- the same core
the web app uses -- so tasks added here show up in the browser and vice
versa. Start the web app first:

    jac run                    # terminal 1 (serves web on /)
    jac run cli -- today       # terminal 2
    jac run cli -- add "Write lab report" --due 2026-10-05 --priority high
    jac run cli -- all
    jac run cli -- login janae       # sign in: CLI then shows YOUR web tasks
    jac run cli -- done "lab"
    jac run cli -- breakdown "lab"
    jac run cli -- delete "lab"
"""

import argparse;
import asyncio;
import json;
import os;
import sys;

import from datetime { date }
import from getpass { getpass }
import from urllib.error { HTTPError }
import from urllib.request { Request, urlopen }

import from jaclang.server.bridge { BridgeError }
import from jaclang.server { sv_client }
import from jaclang.project.config { get_config }
import core.api as api_mod;
import from core.models { Task, Subtask }
import from core.api {
    current_date,
    list_tasks,
    add_task,
    complete_task,
    delete_task,
    rollover_status,
    list_subtasks,
    breakdown
}

glob PROG: str = "nudge",
     EXIT_OK: int = 0,
     EXIT_FAILURE: int = 1,
     EXIT_USAGE: int = 2,
     EXIT_UNAVAILABLE: int = 3;

glob START_HINT: str = "hint: start the app first with `jac run` in another terminal",
     SESSION_FILE: str = ".nudge-session.json";

def warn(text: str) {
    print(text, file=sys.stderr);
}

"""Where the saved login session lives (project root, else cwd)."""
def session_path -> str {
    try {
        cfg = get_config();
        if cfg is not None {
            return os.path.join(str(cfg.project_root), SESSION_FILE);
        }
    } except Exception {}
    return os.path.join(os.getcwd(), SESSION_FILE);
}

"""Saved session ({username, root_id, token}) or {} when absent/unreadable."""
def load_session -> dict[str, any] {
    try {
        p = session_path();
        if not os.path.exists(p) {
            return {};
        }
        with open(p, "r") as f {
            data = json.loads(f.read());
        }
        if isinstance(data, dict) {
            return data;
        }
    } except Exception as e {
        warn("nudge: could not read session " + session_path() + ": " + str(e));
    }
    return {};
}

def save_session(data: dict[str, any]) -> str {
    p = session_path();
    with open(p, "w") as f {
        f.write(json.dumps(data, indent=2));
    }
    try {
        os.chmod(p, 420);  # 0o600 -- the session carries a bearer token
    } except Exception {}
    return p;
}

"""Push an execution context scoped to one account's graph root.

This is the same move the HTTP middleware makes for a logged-in browser
request (`ctx.aset_user_root(root_id)`): every `core.api` call that runs
while this context is current reads and writes THAT root instead of the
anonymous super-root. Returns the token needed to undo it.
"""
def bind_user_root(root_id: str) -> any {
    import from jaclang { JacRuntime }
    import from jaclang.runtime.context { ExecutionContext }
    parent = JacRuntime.get_context();
    ctx = ExecutionContext(_parent=parent);
    ctx.set_user_root(root_id);
    return JacRuntime.push_request_context(ctx);
}

def unbind_user_root(token: any) -> None {
    import from jaclang { JacRuntime }
    JacRuntime.reset_request_context(token);
}

"""POST JSON and parse the {ok, data|error} envelope.

HTTP error statuses (401/422/...) come back as the parsed envelope --
the server answered, so that answer is authoritative. Connection
failures raise, so the caller may retry another base URL.
"""
def http_post_json(url: str, payload: dict[str, any]) -> dict[str, any] {
    body = json.dumps(payload).encode("utf-8");
    req = Request(url, data=body, headers={"Content-Type": "application/json"});
    raw = "";
    try {
        with urlopen(req, timeout=10) as resp {
            raw = resp.read().decode("utf-8");
        }
    } except HTTPError as e {
        raw = "";
        try {
            raw = e.read().decode("utf-8");
        } except Exception {}
    }
    data = json.loads(raw) if raw else {};
    if not isinstance(data, dict) {
        raise ValueError("unexpected response from " + url);
    }
    return data;
}

def fmt(t: Task, n: int) -> str {
    state = "[x]" if t.completed else "[ ]";
    line = "  " + str(n) + " " + state + " " + t.title + "  (" + t.folder_name + ", due " + t.due_date;
    if t.priority == "high" {
        line = line + ", P:high";
    }
    if t.location {
        line = line + ", @" + t.location;
    }
    if t.recurrence {
        line = line + ", " + recur_label(t);
        if t.until {
            line = line + ", stops " + t.until;
        }
        if t.start_time and t.end_time {
            line = line + " (" + t.start_time + "-" + t.end_time + ")";
        }
    }
    return line + ")";
}

"""Human label for a recurrence rule (mirrors core.api's rule shapes)."""
def recur_label(t: Task) -> str {
    r = t.recurrence;
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    if r == "daily" {
        return "↻ daily";
    }
    if r == "weekdays" {
        return "↻ weekdays (Mon-Fri)";
    }
    parts = r.split(":");
    if len(parts) < 2 {
        # legacy rule: anchored to the due date's weekday
        return "↻ every " + days[date.fromisoformat(t.due_date).weekday()];
    }
    kind = parts[0];
    arg = parts[1];
    if kind == "weekly" {
        return "↻ every " + days[int(arg)];
    }
    if kind == "monthly-first" {
        return "↻ 1st " + days[int(arg)] + " of each month";
    }
    if kind == "monthly-date" {
        return "↻ monthly on day " + arg;
    }
    if kind == "annual" {
        p = arg.split("-");
        return "↻ annually " + months[int(p[0]) - 1] + " " + p[1];
    }
    return "↻ " + r;
}

"""0-based index into tasks from a number or a title fragment; -1 on miss."""
def resolve(tasks: list[Task], sel: str) -> int {
    if not sel.strip() {
        warn("nudge: give a task number or a title fragment");
        return -1;
    }
    if sel.isnumeric() {
        i = int(sel);
        if i >= 1 and i <= len(tasks) {
            return i - 1;
        }
        warn("nudge: no task #" + str(i) + " -- run `nudge all` to see numbers");
        return -1;
    }
    low = sel.lower();
    hits: list[int] = [];
    n = 0;
    for t in tasks {
        if low in t.title.lower() {
            hits.append(n);
        }
        n = n + 1;
    }
    if len(hits) == 1 {
        return hits[0];
    }
    if len(hits) == 0 {
        warn("nudge: no task matches " + sel);
        return -1;
    }
    warn(
        "nudge: "
            + sel
            + " matches "
            + str(len(hits))
            + " tasks -- pick a number:"
    );
    for i in hits {
        print("  " + str(i + 1) + ". " + tasks[i].title, file=sys.stderr);
    }
    return -1;
}

async def cmd_add(
    title: str,
    due: str,
    folder: str,
    priority: str,
    place: str,
    recur: str,
    until: str,
    start: str,
    end: str,
) -> int {
    d = due;
    if not d {
        d = await current_date();
    }
    # Shape the --recur choice into a core.api rule: weekly stays anchored
    # to the due weekday; monthly/annual derive their day from the due date.
    rule = recur;
    p = d.split("-");
    if recur == "monthly" {
        rule = "monthly-date:" + str(int(p[2]));
    }
    if recur == "annual" {
        rule = "annual:" + p[1] + "-" + p[2];
    }
    task = await add_task(
        title=title,
        due_date=d,
        folder_name=folder,
        location=place,
        priority=priority,
        recurrence=rule,
        until=until,
        start_time=start,
        end_time=end
    );
    print("added: " + task.title + "  (due " + task.due_date + ", " + task.folder_name + ")");
    subs = await list_subtasks();
    mine: list[Subtask] = [];
    for s in subs {
        if s.task_id == jid(task) {
            mine.append(s);
        }
    }
    if len(mine) > 0 {
        print("nudge: " + task.ai_note);
        for s in mine {
            when = ("due " + s.due_date) if s.due_date else "unscheduled";
            print("  - " + s.title + "  (" + str(s.est_minutes) + " min, " + when + ")");
        }
    }
    return EXIT_OK;
}

async def cmd_today -> int {
    shifted = await rollover_status();
    if shifted > 0 {
        print(
            str(shifted)
                + " overdue task"
                + ("s" if shifted != 1 else "")
                + " nudged to today"
        );
    }
    today = await current_date();
    tasks = await list_tasks();
    print("today (" + today + "):");
    n = 0;
    shown = 0;
    for t in tasks {
        n = n + 1;
        if t.due_date == today {
            print(fmt(t, n));
            shown = shown + 1;
        }
    }
    if shown == 0 {
        print("  nothing due -- add one with: nudge add <title>");
    }
    return EXIT_OK;
}

async def cmd_all -> int {
    tasks = await list_tasks();
    if len(tasks) == 0 {
        print("no tasks yet -- add one with: nudge add <title>");
        return EXIT_OK;
    }
    print("all tasks:");
    n = 0;
    for t in tasks {
        n = n + 1;
        print(fmt(t, n));
    }
    return EXIT_OK;
}

async def cmd_done(target: str) -> int {
    tasks = await list_tasks();
    i = resolve(tasks, target);
    if i < 0 {
        return EXIT_FAILURE;
    }
    updated = await complete_task(jid(tasks[i]));
    if updated is None {
        warn("nudge: task vanished before it could be toggled");
        return EXIT_FAILURE;
    }
    if updated.recurrence {
        if updated.completed {
            # This occurrence is crossed off; its successor is a new
            # independent row -- find the date it landed on (or note
            # that the until stop date ended the series).
            nxt = "";
            fresh = await list_tasks();
            for t2 in fresh {
                if t2.spawned_from == jid(tasks[i]) and not t2.deleted_at {
                    nxt = t2.due_date;
                }
            }
            if nxt {
                print(
                    "done: "
                        + updated.title
                        + " -- "
                        + recur_label(updated)
                        + ", next on "
                        + nxt
                );
            } else {
                print(
                    "done: "
                        + updated.title
                        + " -- "
                        + recur_label(updated)
                        + ", series finished"
                );
            }
        } else {
            print("reopened: " + updated.title);
        }
    } else {
        if updated.completed {
            print("done: " + updated.title);
        } else {
            print("reopened: " + updated.title);
        }
    }
    return EXIT_OK;
}

async def cmd_delete(target: str) -> int {
    tasks = await list_tasks();
    i = resolve(tasks, target);
    if i < 0 {
        return EXIT_FAILURE;
    }
    t = tasks[i];
    res = await delete_task(jid(t));
    if not res {
        warn("nudge: could not delete " + t.title);
        return EXIT_FAILURE;
    }
    print("deleted: " + t.title + "  (moved to the Delete folder -- restorable in the web app)");
    return EXIT_OK;
}

"""Try each API base until one answers; raise if none is reachable."""
def post_to_api(bases: list[str], path: str, payload: dict[str, any]) -> dict[str, any] {
    last: any = None;
    for base in bases {
        url = base.rstrip("/") + path;
        try {
            return http_post_json(url, payload);
        } except Exception as e {
            last = e;
        }
    }
    raise RuntimeError("could not reach the API: " + str(last));
}

async def cmd_login(username: str, password: str, api: str) -> int {
    pw = password;
    if not pw {
        pw = getpass("password for " + username + ": ");
    }
    bases: list[str] = [];
    if api {
        bases.append(api);
    } else {
        bases.append("http://localhost:8001");
        bases.append("http://localhost:8000");
    }
    payload = {
        "identity": {"type": "username", "value": username},
        "credential": {"type": "password", "password": pw}
    };
    try {
        env = post_to_api(bases, "/user/login", payload);
    } except Exception as e {
        warn("nudge: login failed: " + str(e));
        warn(START_HINT);
        return EXIT_UNAVAILABLE;
    }
    if not env.get("ok") {
        warn("nudge: login failed: " + str(env.get("error", "rejected")));
        return EXIT_FAILURE;
    }
    data = env.get("data") or {};
    root_id = str(data.get("root_id", ""));
    token = str(data.get("token", ""));
    if not root_id {
        warn("nudge: login response had no root_id");
        return EXIT_FAILURE;
    }
    p = save_session({
        "username": username,
        "root_id": root_id,
        "token": token
    });
    print("logged in as " + username + " -- `nudge all` now shows your account's tasks");
    print("session saved in " + p);
    return EXIT_OK;
}

async def cmd_logout -> int {
    p = session_path();
    if os.path.exists(p) {
        os.remove(p);
        print("logged out -- CLI is back on the shared anonymous list");
    } else {
        print("no saved session -- already logged out");
    }
    return EXIT_OK;
}

async def cmd_breakdown(target: str) -> int {
    tasks = await list_tasks();
    i = resolve(tasks, target);
    if i < 0 {
        return EXIT_FAILURE;
    }
    task = tasks[i];
    print("breaking down: " + task.title);
    subs = await breakdown(jid(task));
    if len(subs) == 0 {
        print("no steps came back -- is the local byllm model installed?");
        return EXIT_OK;
    }
    n = 0;
    for s in subs {
        n = n + 1;
        when = ("  due " + s.due_date) if s.due_date else "";
        print("  " + str(n) + ". " + s.title + "  (" + str(s.est_minutes) + " min" + when + ")");
    }
    return EXIT_OK;
}

def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Nudge from the terminal -- one shared graph with web and mobile"
    );
    commands = parser.add_subparsers(
        dest="command", metavar="<command>", required=True
    );

    addp = commands.add_parser("add", help="add a task (due date defaults to today)");
    addp.add_argument("title", help="what needs doing");
    addp.add_argument("--due", `default="", help="due date yyyy-mm-dd (default: today)");
    addp.add_argument("--folder", `default="Miscellaneous", help="folder name (auto-created)");
    addp.add_argument("--priority", choices=["high", "medium", "low"], `default="medium");
    addp.add_argument("--location", `default="", help="place / room / address");
    addp.add_argument(
        "--recur",
        choices=["daily", "weekly", "weekdays", "monthly", "annual"],
        `default="",
        help=(
            "repeat rule: daily, weekly (on the due weekday), weekdays "
            "(Mon-Fri), monthly (day taken from --due), annual "
            "(month+day taken from --due)"
        )
    );
    addp.add_argument("--start", `default="", help="start time HH:MM (e.g. 13:00)");
    addp.add_argument("--end", `default="", help="end time HH:MM (e.g. 15:00)");
    addp.add_argument(
        "--until",
        `default="",
        help="stop repeating after this date yyyy-mm-dd (optional)"
    );

    commands.add_parser("today", help="today's tasks after the auto-rollover nudge");
    commands.add_parser("all", help="every task with its selection number");

    donep = commands.add_parser("done", help="toggle a task's completed state");
    donep.add_argument("target", help="task number (from `all`) or title fragment");

    breakp = commands.add_parser(
        "breakdown", help="AI-decompose a task into 15-45 minute micro-steps"
    );
    breakp.add_argument("target", help="task number (from `all`) or title fragment");

    delp = commands.add_parser(
        "delete", help="delete a task (moves it to the Delete folder)"
    );
    delp.add_argument("target", help="task number (from `all`) or title fragment");

    loginp = commands.add_parser(
        "login",
        help="sign in so the CLI reads/writes YOUR account's tasks (same list as web/mobile)"
    );
    loginp.add_argument("username", help="username or email");
    loginp.add_argument("--password", `default="", help="password (prompted if omitted)");
    loginp.add_argument(
        "--api",
        `default="",
        help="API base URL (default: try localhost:8001, then localhost:8000)"
    );
    commands.add_parser("logout", help="sign out and forget the saved session");
    return parser;
}

async def dispatch(ns: argparse.Namespace) -> int {
    try {
        cmd = str(getattr(ns, "command", "") or "");
        if cmd == "add" {
            return await cmd_add(
                title=str(getattr(ns, "title", "") or ""),
                due=str(getattr(ns, "due", "") or ""),
                folder=str(getattr(ns, "folder", "") or "Miscellaneous"),
                priority=str(getattr(ns, "priority", "") or "medium"),
                place=str(getattr(ns, "location", "") or ""),
                recur=str(getattr(ns, "recur", "") or ""),
                until=str(getattr(ns, "until", "") or ""),
                start=str(getattr(ns, "start", "") or ""),
                end=str(getattr(ns, "end", "") or "")
            );
        }
        if cmd == "today" {
            return await cmd_today();
        }
        if cmd == "all" {
            return await cmd_all();
        }
        if cmd == "done" {
            return await cmd_done(str(getattr(ns, "target", "") or ""));
        }
        if cmd == "breakdown" {
            return await cmd_breakdown(str(getattr(ns, "target", "") or ""));
        }
        if cmd == "delete" {
            return await cmd_delete(str(getattr(ns, "target", "") or ""));
        }
        if cmd == "login" {
            return await cmd_login(
                username=str(getattr(ns, "username", "") or ""),
                password=str(getattr(ns, "password", "") or ""),
                api=str(getattr(ns, "api", "") or "")
            );
        }
        if cmd == "logout" {
            return await cmd_logout();
        }
        warn(PROG + ": unknown command");
        return EXIT_USAGE;
    } except BridgeError as e {
        warn("nudge: bridge error: " + str(e));
        warn(START_HINT);
        return EXIT_UNAVAILABLE;
    } except Exception as e {
        warn("nudge: error: " + str(e));
        return EXIT_FAILURE;
    }
}

async def main(argv: list[str]) -> int {
    # The serializer logs one INFO line per cross-app class alias the
    # first time each resolves (see core.models.__jac_schema__ docs) --
    # every run is a fresh process, so keep that chatter off the terminal.
    # Genuine warnings/errors still print.
    try {
        import logging;
        logging.getLogger("jaclang.data.serializer").setLevel(logging.WARNING);
    } except Exception {}
    # Run the shared planner service in this process (colocated), so the
    # terminal uses the exact same core.api code + database as web/mobile.
    try {
        sv_client.register_local("api", api_mod);
    } except Exception as e {
        warn("nudge: could not colocate core.api: " + str(e));
    }
    parser = build_parser();
    ns = parser.parse_args(argv);
    # A saved session scopes every core.api call to that account's graph
    # root -- the same binding the HTTP middleware does for the browser.
    token: any = None;
    session = {} if str(getattr(ns, "command", "")) in ["login", "logout"] else load_session();
    root_id = str(session.get("root_id", "")) if session else "";
    if root_id {
        try {
            token = bind_user_root(root_id);
        } except Exception as e {
            warn("nudge: could not use saved session: " + str(e));
            warn("hint: `nudge logout` then `nudge login <username>` again");
        }
    }
    try {
        return await dispatch(ns);
    } finally {
        if token is not None {
            unbind_user_root(token);
        }
    }
}

with entry:__main__ {
    sys.`exit(asyncio.run(main(sys.argv[1:])));
}
