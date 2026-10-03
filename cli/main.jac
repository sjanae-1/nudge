"""Nudge -- command-line surface.

Every command is a bridged, awaited call into core.api -- the same core
the web app uses -- so tasks added here show up in the browser and vice
versa. Start the web app first:

    jac run                    # terminal 1 (serves web on /)
    jac run cli -- today       # terminal 2
    jac run cli -- add "Write lab report" --due 2026-10-05 --priority high
    jac run cli -- all
    jac run cli -- done "lab"
    jac run cli -- breakdown "lab"
"""

import argparse;
import asyncio;
import sys;

import from jaclang.server.bridge { BridgeError }
import from jaclang.server { sv_client }
import core.api as api_mod;
import from core.models { Task, Subtask }
import from core.api {
    current_date,
    list_tasks,
    add_task,
    complete_task,
    rollover_status,
    list_subtasks,
    breakdown
}

glob PROG: str = "nudge",
     EXIT_OK: int = 0,
     EXIT_FAILURE: int = 1,
     EXIT_USAGE: int = 2,
     EXIT_UNAVAILABLE: int = 3;

glob START_HINT: str = "hint: start the app first with `jac run` in another terminal";

def warn(text: str) {
    print(text, file=sys.stderr);
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
        line = line + ", ↻ weekly";
        if t.start_time and t.end_time {
            line = line + " " + t.start_time + "-" + t.end_time;
        }
    }
    return line + ")";
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
    start: str,
    end: str,
) -> int {
    d = due;
    if not d {
        d = await current_date();
    }
    task = await add_task(
        title=title,
        due_date=d,
        folder_name=folder,
        location=place,
        priority=priority,
        recurrence=recur,
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
                + " past-due task"
                + ("s" if shifted != 1 else "")
                + " rolled over to today"
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
        print(
            "done: "
                + updated.title
                + " -- repeats weekly, next on "
                + updated.due_date
        );
    } else {
        if updated.completed {
            print("done: " + updated.title);
        } else {
            print("reopened: " + updated.title);
        }
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
        choices=["weekly"],
        `default="",
        help="repeat every week (completing rolls to the next occurrence)"
    );
    addp.add_argument("--start", `default="", help="start time HH:MM (e.g. 13:00)");
    addp.add_argument("--end", `default="", help="end time HH:MM (e.g. 15:00)");

    commands.add_parser("today", help="today's tasks after the auto-rollover nudge");
    commands.add_parser("all", help="every task with its selection number");

    donep = commands.add_parser("done", help="toggle a task's completed state");
    donep.add_argument("target", help="task number (from `all`) or title fragment");

    breakp = commands.add_parser(
        "breakdown", help="AI-decompose a task into 15-45 minute micro-steps"
    );
    breakp.add_argument("target", help="task number (from `all`) or title fragment");
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
    # Run the shared planner service in this process (colocated), so the
    # terminal uses the exact same core.api code + database as web/mobile.
    try {
        sv_client.register_local("api", api_mod);
    } except Exception as e {
        warn("nudge: could not colocate core.api: " + str(e));
    }
    parser = build_parser();
    return await dispatch(parser.parse_args(argv));
}

with entry:__main__ {
    sys.`exit(asyncio.run(main(sys.argv[1:])));
}
