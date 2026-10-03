"""Nudge server API -- folders, tasks, subtasks, auto-rollover, AI breakdown.

Every endpoint is `:protect` (authenticated): each logged-in user gets
their own isolated root, so every surface (web, CLI) reads and writes
only that user's planner graph.

Auto-rollover runs lazily inside `list_tasks` instead of as a daemon:
every surface reads the task list on load, so past-due incomplete tasks
are shifted to today before anyone sees them (the spec's
"upon startup or user login" behavior, with zero infrastructure).
"""

import from datetime { date, timedelta }
import from urllib.parse { quote }
import from urllib.request { Request, urlopen }
import from os { environ }
import from json { dumps }
import from core.models { Folder, Task, Subtask, TypeTag }
import from core.ai_engine { PlanStep, SizeReview }

"""Color palette handed out to user-created task types, in order."""
glob TYPE_PALETTE: list[str] = [
    "#e5484d",
    "#f5a623",
    "#3b82f6",
    "#9333ea",
    "#2f9e44",
    "#0097a7",
    "#d81b60",
    "#6d4c41"
];

"""Break a high-level goal into 3-6 micro-tasks of 15-45 minutes each, each paced with its own due date."""
def breakdown_task(goal: str, due_date: str) -> list[PlanStep] by llm();
sem breakdown_task = "Decompose a study or work goal into 3 to 6 concrete micro-tasks, each completable in 15 to 45 minutes, with a realistic estimated duration in minutes and a planned due date (yyyy-mm-dd) for each step, spread between today and the goal's due date and never after it";
sem breakdown_task.goal = "The high-level task to decompose.";
sem breakdown_task.due_date = "The task's own deadline (yyyy-mm-dd); no micro-task may be due after this day.";

"""Judge whether a task is too large for one day; when it is, return paced micro-steps with deadlines."""
def review_task_size(goal: str, due_date: str) -> SizeReview by llm(temperature=0.2);
sem review_task_size = "Decide whether one person could realistically finish this task in a single day or a few hours of work. Anything that needs multiple sessions or more than about four hours is too_large. Examples that are too_large: 'Prepare for organic chemistry final exam', 'Study for finals week', 'Write the lab report', 'Outline my thesis chapter', 'Train for a half marathon', 'Clean out the garage', 'Plan a birthday party'. Examples that are NOT too_large: 'Buy milk', 'Email the professor about a deadline', 'Print the assignment sheet', 'Pack a gym bag'. If it fits in one sitting, set too_large to false and return no steps. If it is too large, set too_large to true with a one-sentence reason, then split it into 3 to 6 concrete micro-tasks of 15 to 45 minutes each, giving each a due date (yyyy-mm-dd) that paces the work from today up to the task's deadline, never past it";
sem review_task_size.goal = "The task title to judge.";
sem review_task_size.due_date = "The task's deadline (yyyy-mm-dd).";

# --- Internal helpers ---

def:priv all_folders -> list[Folder] {
    return [root-->][?:Folder];
}

"""Folders in display order (pos; ties fall back to discovery order)."""
def:priv sorted_folders -> list[Folder] {
    remaining = all_folders();
    out: list[Folder] = [];
    while len(remaining) > 0 {
        bi = 0;
        i = 1;
        while i < len(remaining) {
            if remaining[i].pos < remaining[bi].pos {
                bi = i;
            }
            i = i + 1;
        }
        out.append(remaining[bi]);
        remaining = remaining[:bi] + remaining[bi + 1 :];
    }
    return out;
}

"""Every task attached to any folder (soft-deleted ones included)."""
def:priv all_tasks_raw -> list[Task] {
    return [t for f in all_folders() for t in [f-->][?:Task]];
}

"""Live tasks -- soft-deleted ones stay hidden until restored."""
def:priv all_tasks -> list[Task] {
    out: list[Task] = [];
    for t in all_tasks_raw() {
        if not t.deleted_at {
            out.append(t);
        }
    }
    return out;
}

def:priv folder_named(name: str) -> Folder {
    for f in all_folders() {
        if f.name == name {
            return f;
        }
    }
    return root ++> Folder(name=name);
}

def:priv find_task(id: str) -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            return t;
        }
    }
    return None;
}

def:priv today_str -> str {
    return str(date.today());
}

"""Clamp an AI-proposed step date into [today, goal deadline]."""
def:priv clamp_due(raw: str, latest: str) -> str {
    d = raw.strip();
    if len(d) != 10 or d[4] != "-" or d[7] != "-" {
        d = today_str();
    }
    today = today_str();
    if d < today {
        d = today;
    }
    if d > latest {
        d = latest;
    }
    return d;
}

"""Shift every past-due incomplete task to today. Returns count shifted.

Incomplete subtasks with a past-due date shift too (silently), so the
AI-paced step deadlines keep pacing instead of going stale.
"""
def:priv run_rollover -> int {
    today = today_str();
    shifted = 0;
    for t in all_tasks() {
        if not t.completed and t.due_date < today {
            t.due_date = today;
            shifted = shifted + 1;
        }
        for s in [t-->][?:Subtask] {
            if not s.completed and s.due_date and s.due_date < today {
                s.due_date = today;
            }
        }
    }
    return shifted;
}

"""Seed the default workspace (folders + example tasks) on first use."""
def:priv seed_workspace {
    if len(all_folders()) != 0 {
        return;
    }
    f_eecs = root ++> Folder(name="EECS 449", color="#6c8ebf", pos=0);
    f_math528 = root ++> Folder(name="MATH 528", color="#4caf50", pos=1);
    f_math520 = root ++> Folder(name="MATH 520", color="#ff9800", pos=2);
    f_acc302 = root ++> Folder(name="ACC 302", color="#9c27b0", pos=3);
    f_sam = root ++> Folder(name="SAM", color="#00bcd4", pos=4);
    f_misc = root ++> Folder(name="Miscellaneous", color="#9e9e9e", pos=5);
    # Example tasks so a fresh account opens on a populated planner.
    today = today_str();
    f_math528 ++> Task(
        title="Make cheatsheet for Math 528 Exam",
        due_date=str(date.fromisoformat(today) + timedelta(days=5)),
        folder_name="MATH 528",
        task_type="exam",
        priority="high",
        created_at=today
    );
    f_acc302 ++> Task(
        title="Finish ACC 302 Practice Exam 1",
        due_date=str(date.fromisoformat(today) + timedelta(days=3)),
        folder_name="ACC 302",
        task_type="exam",
        created_at=today
    );
    f_eecs ++> Task(
        title="Design mobile interface for EECS 449 Extra Credit Assignment",
        due_date=str(date.fromisoformat(today) + timedelta(days=4)),
        folder_name="EECS 449",
        task_type="assignment",
        priority="high",
        created_at=today
    );
    f_misc ++> Task(
        title="Grocery shopping",
        due_date=str(date.fromisoformat(today) + timedelta(days=2)),
        folder_name="Miscellaneous",
        created_at=today
    );
}

# --- Folder endpoints ---

"""Today's date (yyyy-mm-dd) -- clients use it for defaults and filters."""
def:protect current_date -> str {
    return today_str();
}

"""All folders in display order (seeds the workspace on first call)."""
def:protect list_folders -> list[Folder] {
    seed_workspace();
    return sorted_folders();
}

"""Create a folder if the name is new, else return the existing one."""
def:protect create_folder(name: str, color: str = "#6c8ebf") -> Folder {
    if not name.strip() {
        raise ValueError("folder name required");
    }
    for f in all_folders() {
        if f.name == name.strip() {
            return f;
        }
    }
    p = 0;
    for f in all_folders() {
        if f.pos + 1 > p {
            p = f.pos + 1;
        }
    }
    return root ++> Folder(name=name.strip(), color=color, pos=p);
}

"""Delete a folder -- only when it has no tasks."""
def:protect delete_folder(name: str) -> dict[str, str] {
    for t in all_tasks() {
        if t.folder_name == name {
            raise ValueError(
                "folder '" + name + "' still has tasks -- move or delete them first"
            );
        }
    }
    for f in all_folders() {
        if f.name == name {
            # Soft-deleted tasks in this folder leave with it (they are
            # already dismissed, so purging them here loses nothing).
            for t in [f-->][?:Task] {
                if t.deleted_at {
                    for s in [t-->][?:Subtask] {
                        del s;
                    }
                    del t;
                }
            }
            del f;
            return {"deleted": name};
        }
    }
    return {};
}

"""Move a folder one slot up (-1) or down (+1) in display order."""
def:protect move_folder(name: str, dirn: int) -> list[Folder] {
    fs = sorted_folders();
    idx = -1;
    n = 0;
    for f in fs {
        if f.name == name {
            idx = n;
        }
        n = n + 1;
    }
    j = idx + dirn;
    if idx < 0 or j < 0 or j >= len(fs) {
        return fs;
    }
    a = fs[idx];
    b = fs[j];
    n = 0;
    for f in fs {
        target = n;
        if jid(f) == jid(a) {
            target = j;
        }
        if jid(f) == jid(b) {
            target = idx;
        }
        f.pos = target;
        n = n + 1;
    }
    return sorted_folders();
}

# --- Custom task types ---

"""User-created task types (the built-ins live client-side)."""
def:protect list_types -> list[TypeTag] {
    return [root-->][?:TypeTag];
}

"""Register a custom type (idempotent by name); auto-assigns a color."""
def:protect create_type(name: str, color: str = "") -> TypeTag {
    clean = name.strip();
    if not clean {
        raise ValueError("type name required");
    }
    existing = [root-->][?:TypeTag];
    for t in existing {
        if t.name.lower() == clean.lower() {
            return t;
        }
    }
    c = color.strip();
    if not c {
        # cycle only over the 4 colors not used by the built-in types
        c = TYPE_PALETTE[4 + len(existing) % 4];
    }
    return root ++> TypeTag(name=clean, color=c);
}

# --- Task endpoints ---

"""All tasks, after running the auto-rollover pass."""
def:protect list_tasks -> list[Task] {
    run_rollover();
    return all_tasks();
}

"""How many past-due incomplete tasks were rolled over (for the UI nudge)."""
def:protect rollover_status -> int {
    return run_rollover();
}

"""AI size review after save: when a task is too large for one day,
split it into dated micro-steps. Best-effort -- if the AI is
unavailable (e.g. local model not installed) the task stays as saved.
"""
def:priv auto_split(task: Task) {
    try {
        review = review_task_size(task.title, task.due_date);
        if not review.too_large or len(review.steps) == 0 {
            return;
        }
        n = 0;
        for step in review.steps {
            task ++> Subtask(
                title=step.title,
                task_id=jid(task),
                est_minutes=step.est_minutes,
                due_date=clamp_due(step.due_date, task.due_date)
            );
            n = n + 1;
        }
        if n > 0 {
            task.ai_note = (
                review.reason or "Too large for one day"
            ) + " -- split into " + str(n) + " paced steps";
        }
    } except Exception as e {
        print("nudge: AI size review unavailable: " + str(e));
        return;
    }
}

"""Add a task. due_date (yyyy-mm-dd) is mandatory by design.

task_type is one of "", exam, quiz, assignment, project.

After the task is saved, an AI size review runs: if the title looks too
large to finish in one day or a few hours, the task comes back already
split into dated micro-steps (`ai_note` says why). If the AI is
unavailable the task still saves normally -- the review is best-effort.
"""
def:protect add_task(
    title: str,
    due_date: str,
    folder_name: str = "Miscellaneous",
    people: str = "",
    location: str = "",
    priority: str = "medium",
    task_type: str = "",
) -> Task {
    if not title.strip() {
        raise ValueError("title is required");
    }
    if not due_date.strip() {
        raise ValueError("due_date is mandatory (yyyy-mm-dd)");
    }
    folder = folder_named(folder_name.strip() or "Miscellaneous");
    task = folder ++> Task(
        title=title.strip(),
        due_date=due_date.strip(),
        folder_name=folder.name,
        people=people,
        location=location,
        priority=priority,
        task_type=task_type.strip().lower(),
        created_at=today_str(),
    );
    auto_split(task);
    return task;
}

"""Toggle a task's completed state."""
def:protect complete_task(id: str) -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            t.completed = not t.completed;
            return t;
        }
    }
    return None;
}

"""Change a task's folder and/or type after creation ("" clears the type)."""
def:protect update_task(id: str, folder_name: str = "", task_type: str = "") -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            if folder_name.strip() {
                t.folder_name = folder_named(folder_name.strip()).name;
            }
            t.task_type = task_type.strip().lower();
            return t;
        }
    }
    return None;
}

"""Push an incomplete task to tomorrow (mobile swipe / CLI / web)."""
def:protect push_task(id: str) -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            t.due_date = str(date.today() + timedelta(days=1));
            return t;
        }
    }
    return None;
}

"""Soft-delete a task: it moves to the Deleted folder for 30 days."""
def:protect delete_task(id: str) -> dict[str, str] {
    for t in all_tasks_raw() {
        if jid(t) == id {
            if not t.deleted_at {
                t.deleted_at = today_str();
            }
            return {"deleted": id};
        }
    }
    return {};
}

"""Move a task out of the Deleted folder back into its folder."""
def:protect restore_task(id: str) -> Task | None {
    for t in all_tasks_raw() {
        if jid(t) == id {
            if t.deleted_at {
                t.deleted_at = "";
                return t;
            }
            return None;
        }
    }
    return None;
}

"""Tasks deleted within the past 30 days (older ones are purged for good)."""
def:protect list_deleted -> list[Task] {
    cutoff = str(date.today() + timedelta(days=-30));
    out: list[Task] = [];
    for t in all_tasks_raw() {
        if t.deleted_at {
            if t.deleted_at < cutoff {
                for s in [t-->][?:Subtask] {
                    del s;
                }
                del t;
            } else {
                out.append(t);
            }
        }
    }
    return out;
}

# --- Subtask endpoints ---

"""Every subtask across all tasks (client groups by task_id)."""
def:protect list_subtasks -> list[Subtask] {
    return [s for t in all_tasks() for s in [t-->][?:Subtask]];
}

"""Toggle a subtask's completed state."""
def:protect toggle_subtask(id: str) -> Subtask | None {
    for t in all_tasks() {
        for s in [t-->][?:Subtask] {
            if jid(s) == id {
                s.completed = not s.completed;
                return s;
            }
        }
    }
    return None;
}

"""Edit a breakdown step's title, due date, and/or time estimate.

est_minutes < 0 means "leave the estimate unchanged".
"""
def:protect update_subtask(
    id: str,
    title: str,
    due_date: str,
    est_minutes: int = -1,
) -> Subtask | None {
    if not title.strip() {
        raise ValueError("step title required");
    }
    d = due_date.strip();
    if d and (len(d) != 10 or d[4] != "-" or d[7] != "-") {
        raise ValueError("due date must be yyyy-mm-dd");
    }
    if est_minutes >= 0 {
        if est_minutes < 1 or est_minutes > 1440 {
            raise ValueError("estimate must be between 1 and 1440 minutes");
        }
    }
    for t in all_tasks() {
        for s in [t-->][?:Subtask] {
            if jid(s) == id {
                s.title = title.strip();
                if d {
                    s.due_date = d;
                }
                if est_minutes >= 0 {
                    s.est_minutes = est_minutes;
                }
                return s;
            }
        }
    }
    return None;
}

"""Delete one breakdown step."""
def:protect delete_subtask(id: str) -> dict[str, str] {
    for t in all_tasks() {
        for s in [t-->][?:Subtask] {
            if jid(s) == id {
                del s;
                return {"deleted": id};
            }
        }
    }
    return {};
}

# --- AI breakdown ---"""AI-decompose a task into micro-step subtasks with paced due dates (replaces prior steps)."""
def:protect breakdown(id: str) -> list[Subtask] {
    task = find_task(id);
    if task is None {
        raise ValueError("no task with id " + id);
    }
    steps = breakdown_task(task.title, task.due_date);
    for s in [task-->][?:Subtask] {
        del s;
    }
    out: list[Subtask] = [];
    for step in steps {
        out.append(
            task ++> Subtask(
                title=step.title,
                task_id=jid(task),
                est_minutes=step.est_minutes,
                due_date=clamp_due(step.due_date, task.due_date)
            )
        );
    }
    return out;
}

# --- Calendar export ---

"""Escape a value for iCalendar text content."""
def:priv ics_escape(raw: str) -> str {
    return raw.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n");
}

"""Incomplete tasks as an all-day-event iCalendar feed (RFC 5545).

Importable directly into Google Calendar (Settings > Import) and macOS
Calendar (File > Import), or any other ICS-consuming calendar app.
"""
def:protect ics_feed -> str {
    out = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Nudge//Personal Planner//EN\r\nCALSCALE:GREGORIAN\r\n";
    for t in all_tasks() {
        if t.completed {
            continue;
        }
        try {
            start = date.fromisoformat(t.due_date);
            end = start + timedelta(days=1);
        } except Exception {
            continue;
        }
        out = out + "BEGIN:VEVENT\r\n";
        out = out + "UID:" + jid(t) + "@nudge\r\n";
        out = out + "DTSTAMP:" + today_str().replace("-", "") + "T000000Z\r\n";
        out = out + "DTSTART;VALUE=DATE:" + str(start).replace("-", "") + "\r\n";
        out = out + "DTEND;VALUE=DATE:" + str(end).replace("-", "") + "\r\n";
        out = out + "SUMMARY:" + ics_escape(t.title) + "\r\n";
        out = out + "DESCRIPTION:" + ics_escape(
            t.folder_name + (" -- " + t.task_type if t.task_type else "")
        ) + "\r\n";
        out = out + "END:VEVENT\r\n";
    }
    out = out + "END:VCALENDAR\r\n";
    return out;
}

"""The ICS feed as a ready-to-use data: URI (client uses it as an <a href>)."""
def:protect ics_download_url -> str {
    return "data:text/calendar;charset=utf-8," + quote(ics_feed());
}

"""A one-event .ics data: URI for a single task.

Works everywhere a calendar file does -- double-clicking imports it into
macOS Calendar; Google Calendar takes it via Settings > Import.
"""
def:protect task_ics_download_url(id: str) -> str {
    task = find_task(id);
    if task is None {
        return "";
    }
    try {
        start = date.fromisoformat(task.due_date);
    } except Exception {
        return "";
    }
    end = start + timedelta(days=1);
    out = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Nudge//Personal Planner//EN\r\nBEGIN:VEVENT\r\n";
    out = out + "UID:" + jid(task) + "@nudge\r\n";
    out = out + "DTSTAMP:" + today_str().replace("-", "") + "T000000Z\r\n";
    out = out + "DTSTART;VALUE=DATE:" + str(start).replace("-", "") + "\r\n";
    out = out + "DTEND;VALUE=DATE:" + str(end).replace("-", "") + "\r\n";
    out = out + "SUMMARY:" + ics_escape(task.title) + "\r\n";
    out = out + "DESCRIPTION:" + ics_escape(task.folder_name) + "\r\n";
    out = out + "END:VEVENT\r\nEND:VCALENDAR\r\n";
    return "data:text/calendar;charset=utf-8," + quote(out);
}

"""Google Calendar 'add event' template URL for one task (all-day)."""
def:protect google_cal_link(id: str) -> str {
    task = find_task(id);
    if task is None {
        return "";
    }
    d = task.due_date.replace("-", "");
    return (
        "https://calendar.google.com/calendar/render?action=TEMPLATE&text="
        + quote(task.title)
        + "&dates="
        + d
        + "/"
        + d
        + "&details="
        + quote("Nudge -- " + task.folder_name)
    );
}

# --- Collaborator email invites ---

"""Split a collaborators string into validated email addresses."""
def:priv parse_emails(raw: str) -> list[str] {
    out: list[str] = [];
    for piece in raw.split(",") {
        e = piece.strip();
        if e {
            if not ("@" in e) or not ("." in e.split("@")[-1]) {
                raise ValueError("'" + e + "' does not look like an email address");
            }
            out.append(e);
        }
    }
    if len(out) == 0 {
        raise ValueError("no email addresses found in the collaborators list");
    }
    return out;
}

"""Minimal HTML escaping for invite email bodies."""
def:priv html_esc(raw: str) -> str {
    return raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
}

"""Send (or preview) the event-invite email for a task's collaborators.

First call with confirmed=False sends nothing -- it returns the
recipients and subject so the UI can show a confirmation notification.
Only a confirmed=True call actually delivers the email through Resend
(RESEND_API_KEY must be set in the server environment).
"""
def:protect invite_collaborators(
    id: str,
    emails: str = "",
    confirmed: bool = False,
) -> dict[str, any] {
    task = find_task(id);
    if task is None {
        raise ValueError("no task with id " + id);
    }
    to = parse_emails(emails or task.people);
    subject = "Invitation: " + task.title;
    if not confirmed {
        return {
            "ok": False,
            "needs_confirm": True,
            "to": to,
            "subject": subject,
        };
    }
    key = environ.get("RESEND_API_KEY", "").strip();
    if not key {
        raise ValueError(
            "email sending is not configured -- set RESEND_API_KEY and restart the server"
        );
    }
    where = "";
    if task.location {
        where = "<p><b>Where:</b> " + html_esc(task.location) + "</p>";
    }
    kind = "";
    if task.task_type {
        kind = " -- " + html_esc(task.task_type);
    }
    body = (
        "<p>You have been invited to:</p>"
        + "<h3>"
        + html_esc(task.title)
        + "</h3>"
        + "<p><b>When:</b> "
        + task.due_date
        + "</p>"
        + where
        + "<p><b>Folder:</b> "
        + html_esc(task.folder_name)
        + kind
        + "</p>"
        + "<p><a href=\""
        + google_cal_link(id)
        + "\">Add it to your Google Calendar</a></p>"
        + "<p>Sent from Nudge -- Personal Planning App.</p>"
    );
    payload = dumps({
        "from": environ.get("RESEND_FROM", "onboarding@resend.dev"),
        "to": to,
        "subject": subject,
        "html": body,
    });
    req = Request(
        "https://api.resend.com/emails",
        data=payload.encode("utf-8"),
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
        },
    );
    try {
        resp = urlopen(req, timeout=15);
        code = resp.status;
        resp.close();
    } except Exception as e {
        raise ValueError("email send failed: " + str(e));
    }
    if code < 200 or code >= 300 {
        raise ValueError("email API returned status " + str(code));
    }
    return {"ok": True, "to": to};
}
