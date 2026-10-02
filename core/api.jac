"""Nudge server API -- folders, tasks, subtasks, auto-rollover, AI breakdown.

Every endpoint is `:pub` (anonymous): this is a single-user personal
planner, so all surfaces (web, mobile, CLI) share the project's graph.

Auto-rollover runs lazily inside `list_tasks` instead of as a daemon:
every surface reads the task list on load, so past-due incomplete tasks
are shifted to today before anyone sees them (the spec's
"upon startup or user login" behavior, with zero infrastructure).
"""

import from datetime { date, timedelta }
import from core.models { Folder, Task, Subtask }
import from core.ai_engine { PlanStep, SizeReview }

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

def:priv all_tasks -> list[Task] {
    return [t for f in all_folders() for t in [f-->][?:Task]];
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

def:priv seed_default_folders {
    if len(all_folders()) == 0 {
        root ++> Folder(name="Inbox", color="#6c8ebf");
        root ++> Folder(name="Coursework", color="#4caf50");
        root ++> Folder(name="Personal", color="#ff9800");
        root ++> Folder(name="Misc", color="#9e9e9e");
    }
}

# --- Folder endpoints ---

"""Today's date (yyyy-mm-dd) -- clients use it for defaults and filters."""
def:pub current_date -> str {
    return today_str();
}

"""All folders (seeds sensible defaults on first run)."""
def:pub list_folders -> list[Folder] {
    seed_default_folders();
    return all_folders();
}

"""Create a folder if the name is new, else return the existing one."""
def:pub create_folder(name: str, color: str = "#6c8ebf") -> Folder {
    if not name.strip() {
        raise ValueError("folder name required");
    }
    for f in all_folders() {
        if f.name == name.strip() {
            return f;
        }
    }
    return root ++> Folder(name=name.strip(), color=color);
}

# --- Task endpoints ---

"""All tasks, after running the auto-rollover pass."""
def:pub list_tasks -> list[Task] {
    run_rollover();
    return all_tasks();
}

"""How many past-due incomplete tasks were rolled over (for the UI nudge)."""
def:pub rollover_status -> int {
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

After the task is saved, an AI size review runs: if the title looks too
large to finish in one day or a few hours, the task comes back already
split into dated micro-steps (`ai_note` says why). If the AI is
unavailable the task still saves normally -- the review is best-effort.
"""
def:pub add_task(
    title: str,
    due_date: str,
    folder_name: str = "Inbox",
    people: str = "",
    room_location: str = "",
    priority: str = "medium",
    energy_level: str = "medium",
) -> Task {
    if not title.strip() {
        raise ValueError("title is required");
    }
    if not due_date.strip() {
        raise ValueError("due_date is mandatory (yyyy-mm-dd)");
    }
    folder = folder_named(folder_name.strip() or "Inbox");
    task = folder ++> Task(
        title=title.strip(),
        due_date=due_date.strip(),
        folder_name=folder.name,
        people=people,
        room_location=room_location,
        priority=priority,
        energy_level=energy_level,
        created_at=today_str(),
    );
    auto_split(task);
    return task;
}

"""Toggle a task's completed state."""
def:pub complete_task(id: str) -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            t.completed = not t.completed;
            return t;
        }
    }
    return None;
}

"""Push an incomplete task to tomorrow (mobile swipe / CLI / web)."""
def:pub push_task(id: str) -> Task | None {
    for t in all_tasks() {
        if jid(t) == id {
            t.due_date = str(date.today() + timedelta(days=1));
            return t;
        }
    }
    return None;
}

"""Delete a task and its subtasks."""
def:pub delete_task(id: str) -> dict[str, str] {
    for t in all_tasks() {
        if jid(t) == id {
            for s in [t-->][?:Subtask] {
                del s;
            }
            del t;
            return {"deleted": id};
        }
    }
    return {};
}

# --- Subtask endpoints ---

"""Every subtask across all tasks (client groups by task_id)."""
def:pub list_subtasks -> list[Subtask] {
    return [s for t in all_tasks() for s in [t-->][?:Subtask]];
}

"""Toggle a subtask's completed state."""
def:pub toggle_subtask(id: str) -> Subtask | None {
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

# --- AI breakdown ---"""AI-decompose a task into micro-step subtasks with paced due dates (replaces prior steps)."""
def:pub breakdown(id: str) -> list[Subtask] {
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
