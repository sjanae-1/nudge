"""Nudge -- web frontend (single-page app).

State-driven list view with folder chips, quick filters, quick-add,
AI size review (oversized tasks arrive pre-split into dated micro-steps),
manual breakdown, and the auto-rollover nudge banner.
"""

import "./styles.css";
import from core.api {
    Folder,
    Task,
    Subtask,
    current_date,
    list_folders,
    create_folder,
    list_tasks,
    add_task,
    complete_task,
    push_task,
    delete_task,
    list_subtasks,
    toggle_subtask,
    rollover_status,
    breakdown
}

def:pub app -> JsxElement {
    has folders: list[Folder] = [],
        tasks: list[Task] = [],
        subs: list[Subtask] = [],
        today: str = "",
        quick: str = "today",
        folder_filter: str = "",
        new_title: str = "",
        new_due: str = "",
        new_folder: str = "Inbox",
        new_people: str = "",
        new_room: str = "",
        new_priority: str = "medium",
        new_energy: str = "medium",
        show_meta: bool = False,
        new_folder_name: str = "",
        expanded: str = "",
        rollover_note: str = "",
        loading: bool = True,
        error: str = "";

    # Load everything once, then reuse refresh() after every mutation.
    async can with entry {
        try {
            d = await current_date();
            today = d;
            new_due = d;
            rollover_note = "";
            shifted = await rollover_status();
            if shifted > 0 {
                rollover_note = (
                    str(shifted)
                    + " past-due task"
                    + ("s" if shifted != 1 else "")
                    + " rolled over to today"
                );
            }
            folders = await list_folders();
            tasks = await list_tasks();
            subs = await list_subtasks();
        } except Exception as e {
            error = str(e);
        } finally {
            loading = False;
        }
    }

    async def refresh {
        folders = await list_folders();
        tasks = await list_tasks();
        subs = await list_subtasks();
    }

    async def do_add {
        error = "";
        if not new_title.strip() {
            error = "Give the task a title";
            return;
        }
        if not new_due.strip() {
            error = "A due date is required";
            return;
        }
        try {
            t = await add_task(
                title=new_title.strip(),
                due_date=new_due.strip(),
                folder_name=new_folder,
                people=new_people,
                room_location=new_room,
                priority=new_priority,
                energy_level=new_energy
            );
            new_title = "";
            new_people = "";
            new_room = "";
            new_priority = "medium";
            new_energy = "medium";
            show_meta = False;
            # Surface any AI-created steps for the task we just added.
            expanded = jid(t);
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_toggle(id: str) {
        try {
            await complete_task(id);
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_push(id: str) {
        try {
            await push_task(id);
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_delete(id: str) {
        try {
            await delete_task(id);
            if expanded == id {
                expanded = "";
            }
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_breakdown(id: str) {
        error = "";
        try {
            await breakdown(id);
            expanded = id;
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_toggle_sub(id: str) {
        try {
            await toggle_subtask(id);
            subs = await list_subtasks();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_add_folder {
        error = "";
        try {
            f = await create_folder(name=new_folder_name);
            new_folder = f.name;
            new_folder_name = "";
            folders = await list_folders();
        } except Exception as e {
            error = str(e);
        }
    }

    def task_subs(task_id: str) -> list[Subtask] {
        out: list[Subtask] = [];
        for s in subs {
            if s.task_id == task_id {
                out.append(s);
            }
        }
        return out;
    }

    def visible_tasks -> list[Task] {
        out: list[Task] = [];
        for t in tasks {
            if folder_filter and t.folder_name != folder_filter {
                continue;
            }
            if quick == "today" and t.due_date != today {
                continue;
            }
            if quick == "upcoming" and not (t.due_date > today) {
                continue;
            }
            if quick == "focus" and t.priority != "high" {
                continue;
            }
            out.append(t);
        }
        return out;
    }

    def folder_color(name: str) -> str {
        for f in folders {
            if f.name == name {
                return f.color;
            }
        }
        return "#9e9e9e";
    }

    def count_due_today -> int {
        n = 0;
        for t in tasks {
            if not t.completed and t.due_date == today {
                n = n + 1;
            }
        }
        return n;
    }

    def count_upcoming -> int {
        n = 0;
        for t in tasks {
            if not t.completed and t.due_date > today {
                n = n + 1;
            }
        }
        return n;
    }

    def count_done -> int {
        n = 0;
        for t in tasks {
            if t.completed {
                n = n + 1;
            }
        }
        return n;
    }

    def view_title -> str {
        if quick == "today" {
            return "Today";
        }
        if quick == "upcoming" {
            return "Upcoming";
        }
        if quick == "focus" {
            return "High Focus";
        }
        return "All tasks";
    }

    if loading {
        return <div class="np-loading">Loading your plans...</div>;
    }

    return
        <div class="np-app">
            <header class="np-header">
                <h1>Nudge</h1>
                <span class="np-tagline">Personal Planning App built for College Students</span>
                {(<span class="np-rollover">{rollover_note}</span>)
                    if rollover_note
                    else None}
            </header>
            {(<div class="np-error">{error}</div>) if error else None}

            <div class="np-stats">
                <span class="np-stat">
                    <strong>{count_due_today()}</strong> due today
                </span>
                <span class="np-stat">
                    <strong>{count_upcoming()}</strong> upcoming
                </span>
                <span class="np-stat">
                    <strong>{len(folders)}</strong> folders
                </span>
                <span class="np-stat np-stat-done">
                    <strong>{count_done()}</strong> done
                </span>
            </div>

            <div class="np-body">
                <aside class="np-sidebar">
                    <div class="np-side-title">Views</div>
                    {[
                        <button
                            key={q}
                            class={
                                "np-chip " + ("np-chip-on" if quick == q else "")
                            }
                            onClick={lambda { quick = q; }}
                        >
                            {label}
                        </button>
                        for (q, label) in [
                            ("today", "Today"),
                            ("upcoming", "Upcoming"),
                            ("focus", "High Focus"),
                            ("all", "All")
                        ]
                    ]}
                    <div class="np-side-title">Folders</div>
                    <button
                        class={
                            "np-chip " + ("np-chip-on" if not folder_filter else "")
                        }
                        onClick={lambda { folder_filter = ""; }}
                    >
                        All folders
                    </button>
                    {[
                        <button
                            key={f.name}
                            class={
                                "np-chip "
                                    + ("np-chip-on" if folder_filter == f.name else "")
                            }
                            onClick={lambda { folder_filter = f.name; }}
                        >
                            <span
                                class="np-dot"
                                style={{"backgroundColor": f.color}}
                            />
                            {f.name}
                        </button>
                        for f in folders
                    ]}
                    <div class="np-newfolder">
                        <input
                            value={new_folder_name}
                            onChange={lambda (e: ChangeEvent) {
                                new_folder_name = e.target.value;
                            }}
                            placeholder="+ new folder"
                        />
                        <button onClick={lambda { do_add_folder(); }}>Add</button>
                    </div>
                </aside>

                <main class="np-main">
                    <div class="np-viewhead">
                        <span class="np-viewtitle">{view_title()}</span>
                        <span class="np-count">
                            {str(len(visible_tasks()))
                                + " shown"
                                + (" · folder: " + folder_filter)
                                if folder_filter
                                else str(len(visible_tasks())) + " shown"}
                        </span>
                    </div>
                    <div class="np-addcard">
                        <input
                            class="np-add-title"
                            value={new_title}
                            onChange={lambda (e: ChangeEvent) {
                                new_title = e.target.value;
                            }}
                            onKeyPress={lambda (e: KeyboardEvent) {
                                if e.key == "Enter" { do_add(); }
                            }}
                            placeholder="What needs doing?"
                        />
                        <input
                            type="date"
                            class="np-add-due"
                            value={new_due}
                            onChange={lambda (e: ChangeEvent) {
                                new_due = e.target.value;
                            }}
                        />
                        <select
                            class="np-add-folder"
                            value={new_folder}
                            onChange={lambda (e: ChangeEvent) {
                                new_folder = e.target.value;
                            }}
                        >
                            {[
                                <option key={f.name} value={f.name}>{f.name}</option>
                                for f in folders
                            ]}
                        </select>
                        <button class="np-add-btn" onClick={lambda { do_add(); }}>
                            Add
                        </button>
                        <button
                            class="np-meta-toggle"
                            onClick={lambda { show_meta = not show_meta; }}
                        >
                            {("Less" if show_meta else "Details")}
                        </button>
                        {(<div class="np-add-meta">
                            <input
                                value={new_room}
                                onChange={lambda (e: ChangeEvent) {
                                    new_room = e.target.value;
                                }}
                                placeholder="Room (e.g. Shapiro 3rd floor)"
                            />
                            <input
                                value={new_people}
                                onChange={lambda (e: ChangeEvent) {
                                    new_people = e.target.value;
                                }}
                                placeholder="Collaborators (comma separated)"
                            />
                            <select
                                value={new_priority}
                                onChange={lambda (e: ChangeEvent) {
                                    new_priority = e.target.value;
                                }}
                            >
                                <option value="high">Priority: high</option>
                                <option value="medium">Priority: medium</option>
                                <option value="low">Priority: low</option>
                            </select>
                            <select
                                value={new_energy}
                                onChange={lambda (e: ChangeEvent) {
                                    new_energy = e.target.value;
                                }}
                            >
                                <option value="high">Energy: high focus</option>
                                <option value="medium">Energy: medium</option>
                                <option value="low">Energy: low</option>
                            </select>
                        </div>) if show_meta else None}
                    </div>

                    {(<div class="np-empty">
                        Nothing here -- add a task or switch filters.
                    </div>) if len(visible_tasks()) == 0
                        else [
                            <div class="np-task" key={jid(t)}>
                                <div class="np-task-row">
                                    <input
                                        type="checkbox"
                                        checked={t.completed}
                                        onChange={lambda { do_toggle(jid(t)); }}
                                    />
                                    <span
                                        class={
                                            "np-title "
                                                + ("np-done" if t.completed else "")
                                        }
                                        title="Show steps"
                                        onClick={lambda {
                                            expanded = (
                                                ""
                                                if expanded == jid(t)
                                                else jid(t)
                                            );
                                        }}
                                    >
                                        {t.title}
                                    </span>
                                    <span
                                        class="np-badge"
                                        style={{"backgroundColor": folder_color(t.folder_name)}}
                                    >
                                        {t.folder_name}
                                    </span>
                                    <span
                                        class={
                                            "np-due "
                                                + ("np-due-today" if t.due_date == today else "")
                                        }
                                    >
                                        {t.due_date}
                                    </span>
                                    {(<span class="np-pri">P:high</span>)
                                        if t.priority == "high"
                                        else None}
                                    <span class="np-energy">{t.energy_level}</span>
                                    {(<span class="np-room">{t.room_location}</span>)
                                        if t.room_location
                                        else None}
                                    {(<span class="np-people">{t.people}</span>)
                                        if t.people
                                        else None}
                                    <span class="np-actions">
                                        <button
                                            class="np-ai"
                                            title="AI breakdown"
                                            onClick={lambda { do_breakdown(jid(t)); }}
                                        >
                                            break down
                                        </button>
                                        <button
                                            onClick={lambda { do_push(jid(t)); }}
                                            title="Push to tomorrow"
                                        >
                                            tomorrow
                                        </button>
                                        <button
                                            class="np-del"
                                            onClick={lambda { do_delete(jid(t)); }}
                                        >
                                            x
                                        </button>
                                    </span>
                                </div>
                                {(<div class="np-ainote">{t.ai_note}</div>)
                                    if t.ai_note
                                    else None}
                                {(<div class="np-subs">
                                    {(<span class="np-sub-hint">
                                        No steps yet -- hit "break down"
                                    </span>) if len(task_subs(jid(t))) == 0
                                        else [
                                                <label class="np-sub" key={jid(s)}>
                                                    <input
                                                        type="checkbox"
                                                        checked={s.completed}
                                                        onChange={lambda {
                                                            do_toggle_sub(jid(s));
                                                        }}
                                                    />
                                                    <span
                                                        class={
                                                            "np-sub-title "
                                                                + ("np-done" if s.completed else "")
                                                        }
                                                    >
                                                        {s.title}
                                                    </span>
                                                    <span class="np-est">
                                                        {s.est_minutes} min
                                                    </span>
                                                    {(<span class="np-sub-due">
                                                        {s.due_date}
                                                    </span>)
                                                        if s.due_date
                                                        else None}
                                                </label>
                                            for s in task_subs(jid(t))
                                        ]}
                                    </div>) if expanded == jid(t) else None}
                            </div>
                            for t in visible_tasks()
                        ]}
                </main>
            </div>

            <footer class="np-footer">
                One core, three surfaces -- this page, the CLI, and mobile all
                read and write the same planner graph.
                <br />
                CLI: <code>jac run cli -- today</code>
                &nbsp;|&nbsp; <code>jac run cli -- add "..."</code>
                &nbsp;|&nbsp; <code>jac run cli -- breakdown &lt;task&gt;</code>
            </footer>
        </div>;
}
