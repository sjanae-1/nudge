"""Nudge -- the planner (protected route, auth-guarded group).

List/calendar views with folder chips, a buffer-controlled Today view,
quick-add with type tags, AI size review (oversized tasks arrive
pre-split into dated micro-steps), and .ics / Google Calendar export.
"""

import from "@jac/runtime" { jacLogout, Navigate }

# Node types (Folder/Task/...) cross the api service boundary as plain
# serialized records, so they are annotated as `any` client-side.

import from core.api {
    current_date,
    list_folders,
    create_folder,
    delete_folder,
    move_folder,
    list_types,
    create_type,
    list_tasks,
    add_task,
    complete_task,
    update_task,
    delete_task,
    list_subtasks,
    toggle_subtask,
    update_subtask,
    delete_subtask,
    rollover_status,
    breakdown,
    ics_download_url,
    task_ics_download_url,
    list_deleted,
    restore_task,
    invite_collaborators
}

glob MONTHS: list[str] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
];

# --- Pure date helpers (client-safe: integer math only, no datetime) ---

def pad2(n: int) -> str {
    if n < 10 {
        return "0" + str(n);
    }
    return str(n);
}

def leap(y: int) -> bool {
    if y % 400 == 0 {
        return True;
    }
    if y % 100 == 0 {
        return False;
    }
    return y % 4 == 0;
}

def days_in_month(y: int, m: int) -> int {
    if m == 2 {
        if leap(y) {
            return 29;
        }
        return 28;
    }
    if m == 4 or m == 6 or m == 9 or m == 11 {
        return 30;
    }
    return 31;
}

"""Days since 1970-01-01 (a Thursday)."""
def day_index(y: int, m: int, d: int) -> int {
    n = 0;
    if y >= 1970 {
        yy = 1970;
        while yy < y {
            if leap(yy) {
                n = n + 366;
            } else {
                n = n + 365;
            }
            yy = yy + 1;
        }
    } else {
        yy = y;
        while yy < 1970 {
            if leap(yy) {
                n = n - 366;
            } else {
                n = n - 365;
            }
            yy = yy + 1;
        }
    }
    mm = 1;
    while mm < m {
        n = n + days_in_month(y, mm);
        mm = mm + 1;
    }
    return n + d - 1;
}

"""yyyy-mm-dd plus n days (n may be negative)."""
def ymd_add(s: str, n: int) -> str {
    p = s.split("-");
    y = int(p[0]);
    m = int(p[1]);
    d = int(p[2]) + n;
    while d > days_in_month(y, m) {
        d = d - days_in_month(y, m);
        m = m + 1;
        if m > 12 {
            m = 1;
            y = y + 1;
        }
    }
    while d < 1 {
        m = m - 1;
        if m < 1 {
            m = 12;
            y = y - 1;
        }
        d = d + days_in_month(y, m);
    }
    return str(y) + "-" + pad2(m) + "-" + pad2(d);
}

"""Google Calendar add-event template URL (all-day) for a task."""
def gcal_href(t: any) -> str {
    d = t.due_date.replace("-", "");
    title = t.title.replace("&", "%26").replace("#", "%23").replace("?", "%3F").replace(" ", "%20");
    return (
        "https://calendar.google.com/calendar/render?action=TEMPLATE&text="
        + title
        + "&dates="
        + d
        + "/"
        + d
        + "&details=Nudge"
    );
}

"""Google Maps directions URL for a task's location (travel-time estimate)."""
def maps_href(place: str) -> str {
    q = place.replace("&", "%26").replace(",", "%2C").replace(" ", "%20");
    return "https://www.google.com/maps/dir/?api=1&destination=" + q;
}

"""True when a bridge failure means the session token is dead (stale
account / reset store) -- the UI should sign out, not show raw JSON."""
def is_auth_error(msg: str) -> bool {
    return (
        "UNAUTHORIZED" in msg
        or "unknown user" in msg
        or "IDENTITY_" in msg
    );
}

def:pub Planner -> JsxPage {
    has folders: list[any] = [],
        tasks: list[any] = [],
        subs: list[any] = [],
        today: str = "",
        quick: str = "today",
        folder_filter: str = "",
        buf_days: int = 3,
        new_title: str = "",
        new_due: str = "",
        new_folder: str = "Miscellaneous",
        new_people: str = "",
        new_location: str = "",
        new_priority: str = "medium",
        new_type: str = "",
        show_meta: bool = False,
        new_folder_name: str = "",
        expanded: str = "",
        rollover_note: str = "",
        loading: bool = True,
        busy: str = "",
        error: str = "",
        cal: bool = False,
        cal_y: int = 2026,
        cal_m: int = 1,
        ics_url: str = "",
        ics_one: str = "",
        leave: bool = False,
        types: list[any] = [],
        manage_f: bool = False,
        type_target: str = "",
        folder_target: str = "",
        new_type_name: str = "",
        editing_sub: str = "",
        ed_sub_title: str = "",
        ed_sub_due: str = "",
        ed_sub_est: str = "",
        buf_unit: str = "days",
        special: str = "",
        trash: list[any] = [],
        cal_menu: str = "",
        invite_for: str = "",
        invite_to: str = "",
        invite_stage: str = "",
        note: str = "";

    # Load everything once, then reuse refresh() after every mutation.
    async can with entry {
        try {
            d = await current_date();
            today = d;
            new_due = d;
            p = d.split("-");
            cal_y = int(p[0]);
            cal_m = int(p[1]);
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
            types = await list_types();
            tasks = await list_tasks();
            subs = await list_subtasks();
            trash = await list_deleted();
        } except Exception as e {
            if is_auth_error(str(e)) {
                # Stale/dead session token: sign out cleanly instead of
                # surfacing the raw bridge error banner.
                jacLogout();
                leave = True;
            } else {
                error = str(e);
            }
        } finally {
            loading = False;
        }
    }

    async def refresh {
        folders = await list_folders();
        types = await list_types();
        tasks = await list_tasks();
        subs = await list_subtasks();
        trash = await list_deleted();
        # Leave Done / Deleted automatically when they empty out.
        if special == "done" and count_done() == 0 {
            special = "";
        }
        if special == "deleted" and len(trash) == 0 {
            special = "";
        }
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
        busy = "add";
        try {
            t = await add_task(
                title=new_title.strip(),
                due_date=new_due.strip(),
                folder_name=new_folder,
                people=new_people,
                location=new_location,
                priority=new_priority,
                task_type=new_type
            );
            new_title = "";
            new_people = "";
            new_location = "";
            new_priority = "medium";
            new_type = "";
            show_meta = False;
            # Surface any AI-created steps for the task we just added.
            await do_expand(jid(t));
            await refresh();
        } except Exception as e {
            error = str(e);
        } finally {
            busy = "";
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

    async def do_delete(id: str) {
        try {
            await delete_task(id);
            if expanded == id {
                expanded = "";
            }
            cal_menu = "";
            if invite_for == id {
                invite_stage = "";
                invite_for = "";
                invite_to = "";
            }
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_breakdown(id: str) {
        error = "";
        busy = id;
        try {
            await breakdown(id);
            expanded = id;
            await refresh();
        } except Exception as e {
            error = str(e);
        } finally {
            busy = "";
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
            target = folder_target;
            new_folder_name = "";
            folder_target = "";
            folders = await list_folders();
            if target == "new" {
                new_folder = f.name;
            } elif target {
                kind = "";
                for w in tasks {
                    if jid(w) == target {
                        kind = w.task_type;
                    }
                }
                await update_task(
                    id=target,
                    folder_name=f.name,
                    task_type=kind
                );
                await refresh();
            } else {
                new_folder = f.name;
            }
        } except Exception as e {
            error = str(e);
        }
    }

    async def toggle_cal {
        error = "";
        cal = not cal;
        if cal {
            special = "";
            cal_menu = "";
        }
        if cal and not ics_url {
            try {
                ics_url = await ics_download_url();
            } except Exception as e {
                error = str(e);
            }
        }
    }

    def cal_step(dirn: int) {
        m = cal_m + dirn;
        y = cal_y;
        if m < 1 {
            m = 12;
            y = y - 1;
        }
        if m > 12 {
            m = 1;
            y = y + 1;
        }
        cal_m = m;
        cal_y = y;
    }

    def do_logout {
        jacLogout();
        leave = True;
    }

    async def do_expand(id: str) {
        if expanded == id {
            expanded = "";
            ics_one = "";
            cal_menu = "";
            return;
        }
        expanded = id;
        ics_one = "";
        cal_menu = "";
        try {
            ics_one = await task_ics_download_url(id=id);
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_delete_folder(name: str) {
        error = "";
        try {
            await delete_folder(name=name);
            if folder_filter == name {
                folder_filter = "";
            }
            if new_folder == name {
                new_folder = "Miscellaneous";
            }
            folders = await list_folders();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_move_folder(name: str, dirn: int) {
        error = "";
        try {
            folders = await move_folder(name=name, dirn=dirn);
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_create_type {
        error = "";
        try {
            t = await create_type(name=new_type_name);
            target = type_target;
            new_type_name = "";
            type_target = "";
            types = await list_types();
            if target == "new" {
                new_type = t.name.lower();
            } elif target {
                fname = "";
                for w in tasks {
                    if jid(w) == target {
                        fname = w.folder_name;
                    }
                }
                await update_task(
                    id=target,
                    folder_name=fname,
                    task_type=t.name.lower()
                );
                await refresh();
            }
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_update_task(id: str, folder: str, kind: str) {
        error = "";
        try {
            await update_task(id=id, folder_name=folder, task_type=kind);
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    def start_edit_sub(s: any) {
        editing_sub = jid(s);
        ed_sub_title = s.title;
        ed_sub_due = s.due_date;
        ed_sub_est = str(s.est_minutes);
    }

    async def do_save_sub(id: str) {
        error = "";
        est = -1;
        if ed_sub_est.strip() {
            try {
                est = int(ed_sub_est);
            } except Exception {
                error = "Estimated minutes must be a whole number";
                return;
            }
        }
        try {
            await update_subtask(
                id=id,
                title=ed_sub_title,
                due_date=ed_sub_due,
                est_minutes=est
            );
            editing_sub = "";
            subs = await list_subtasks();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_delete_sub(id: str) {
        error = "";
        try {
            await delete_subtask(id=id);
            subs = await list_subtasks();
        } except Exception as e {
            error = str(e);
        }
    }

    async def do_restore(id: str) {
        error = "";
        try {
            await restore_task(id=id);
            await refresh();
        } except Exception as e {
            error = str(e);
        }
    }

    def toggle_cal_menu(id: str) {
        if cal_menu == id {
            cal_menu = "";
        } else {
            cal_menu = id;
        }
    }

    """One dropdown per setting: '+ add new ...' opens the inline input."""
    def pick_new_type(v: str) {
        if v == "__add__" {
            type_target = "new";
        } else {
            type_target = "";
            new_type = v;
        }
    }

    def pick_new_folder(v: str) {
        if v == "__add__" {
            folder_target = "new";
        } else {
            folder_target = "";
            new_folder = v;
        }
    }

    def pick_task_type(id: str, folder: str, v: str) {
        if v == "__add__" {
            type_target = id;
        } else {
            type_target = "";
            do_update_task(id, folder, v);
        }
    }

    def pick_task_folder(id: str, kind: str, v: str) {
        if v == "__add__" {
            folder_target = id;
        } else {
            folder_target = "";
            do_update_task(id, v, kind);
        }
    }

    def cancel_new_type {
        type_target = "";
        new_type_name = "";
    }

    def cancel_new_folder {
        folder_target = "";
        new_folder_name = "";
    }

    """Fill-in-the-blank buffer size (guards int('') on empty input)."""
    def set_buf_days(v: str) {
        if v.strip() {
            try {
                buf_days = int(v);
            } except Exception {
                buf_days = 0;
            }
        } else {
            buf_days = 0;
        }
    }

    def buf_total -> int {
        if buf_unit == "weeks" {
            return buf_days * 7;
        }
        return buf_days;
    }

    def buf_label -> str {
        if buf_days == 0 {
            return "due today";
        }
        if buf_unit == "weeks" {
            return "due in " + str(buf_days)
                + (" week" if buf_days == 1 else " weeks");
        }
        return "due in " + str(buf_days)
            + (" day" if buf_days == 1 else " days");
    }

    """Preview the invite (server validates the addresses) -- no send yet."""
    async def start_invite(id: str, raw: str) {
        error = "";
        note = "";
        try {
            r = await invite_collaborators(id=id, emails=raw, confirmed=False);
            to = "";
            for e in r["to"] {
                if to {
                    to = to + ", " + e;
                } else {
                    to = e;
                }
            }
            invite_for = id;
            invite_to = to;
            invite_stage = "confirm";
        } except Exception as e {
            invite_stage = "";
            invite_for = "";
            invite_to = "";
            error = str(e);
        }
    }

    async def do_invite {
        error = "";
        busy = "invite";
        try {
            await invite_collaborators(
                id=invite_for,
                emails=invite_to,
                confirmed=True
            );
            note = "Invite sent to " + invite_to;
            invite_stage = "";
            invite_for = "";
            invite_to = "";
        } except Exception as e {
            error = str(e);
            invite_stage = "";
            invite_for = "";
            invite_to = "";
        } finally {
            busy = "";
        }
    }

    def dismiss_note {
        note = "";
    }

    def type_color(kind: str) -> str {
        if kind == "exam" {
            return "#e5484d";
        }
        if kind == "quiz" {
            return "#f5a623";
        }
        if kind == "assignment" {
            return "#3b82f6";
        }
        if kind == "project" {
            return "#9333ea";
        }
        for t in types {
            if t.name.lower() == kind {
                return t.color;
            }
        }
        return "#9e9e9e";
    }

    def type_label(kind: str) -> str {
        if kind == "exam" {
            return "Exam";
        }
        if kind == "quiz" {
            return "Quiz";
        }
        if kind == "assignment" {
            return "Assignment";
        }
        if kind == "project" {
            return "Project";
        }
        for t in types {
            if t.name.lower() == kind {
                return t.name;
            }
        }
        return "";
    }

    def custom_types -> list[any] {
        out: list[any] = [];
        for t in types {
            n = t.name.lower();
            if n != "exam"
                and n != "quiz"
                and n != "assignment"
                and n != "project"
            {
                out.append(t);
            }
        }
        return out;
    }

    def task_subs(task_id: str) -> list[any] {
        out: list[any] = [];
        for s in subs {
            if s.task_id == task_id {
                out.append(s);
            }
        }
        return out;
    }

    def visible_tasks -> list[any] {
        if special == "done" {
            done_list: list[any] = [];
            for t in tasks {
                if t.completed {
                    done_list.append(t);
                }
            }
            return done_list;
        }
        cutoff = today;
        if quick == "today" and today {
            cutoff = ymd_add(today, buf_total());
        }
        if quick == "week" and today {
            cutoff = ymd_add(today, 7);
        }
        out: list[any] = [];
        for t in tasks {
            if t.completed {
                continue;
            }
            if folder_filter and t.folder_name != folder_filter {
                continue;
            }
            if quick != "all" and t.due_date > cutoff {
                continue;
            }
            out.append(t);
        }
        return out;
    }

    def shown_count -> int {
        if special == "deleted" {
            return len(trash);
        }
        return len(visible_tasks());
    }

    def folder_color(name: str) -> str {
        for f in folders {
            if f.name == name {
                return f.color;
            }
        }
        return "#9e9e9e";
    }

    def count_due_soon -> int {
        if not today {
            return 0;
        }
        cutoff = ymd_add(today, buf_total());
        n = 0;
        for t in tasks {
            if not t.completed and t.due_date <= cutoff {
                n = n + 1;
            }
        }
        return n;
    }

    def count_week -> int {
        if not today {
            return 0;
        }
        cutoff = ymd_add(today, 7);
        n = 0;
        for t in tasks {
            if not t.completed and t.due_date <= cutoff {
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
        if special == "done" {
            return "Done";
        }
        if special == "deleted" {
            return "Deleted";
        }
        if quick == "today" {
            return "Today";
        }
        if quick == "week" {
            return "This week";
        }
        return "All tasks";
    }

    def tasks_on(ymd: str) -> list[any] {
        out: list[any] = [];
        for t in tasks {
            if t.due_date == ymd {
                out.append(t);
            }
        }
        return out;
    }

    def day_cell(y: int, m: int, d: int) -> any {
        ymd = str(y) + "-" + pad2(m) + "-" + pad2(d);
        on = tasks_on(ymd);
        cls = "np-calcell " + ("np-caltoday" if ymd == today else "");
        return
            <div class={cls} key={"d" + str(d)}>
                <span class="np-cald">{d}</span>
                {[
                    <button
                        class="np-caltask"
                        key={jid(t)}
                        style={{"backgroundColor": type_color(t.task_type)}}
                        title={t.title}
                        onClick={lambda {
                            quick = "all";
                            folder_filter = "";
                            cal = False;
                            do_expand(jid(t));
                        }}
                    >
                        {t.title}
                    </button>
                    for t in on
                ]}
            </div>;
    }

    def cal_grid -> list[any] {
        out: list[any] = [];
        lead = (4 + day_index(cal_y, cal_m, 1)) % 7;
        i = 0;
        while i < lead {
            out.append(<div class="np-calcell np-calblank" key={"b" + str(i)} />);
            i = i + 1;
        }
        d = 1;
        while d <= days_in_month(cal_y, cal_m) {
            out.append(day_cell(cal_y, cal_m, d));
            d = d + 1;
        }
        while len(out) % 7 != 0 {
            out.append(
                <div
                    class="np-calcell np-calblank"
                    key={"t" + str(len(out))}
                />
            );
        }
        return out;
    }

    if leave {
        return <Navigate to="/login" replace={True} />;
    }

    if loading {
        return <div class="np-loading">Loading your plans...</div>;
    }

    return
        <div class="np-app">
            <header class="np-header">
                <div class="np-brand">
                    <h1>Nudge</h1>
                    <span class="np-tagline">Personal Planning App built for College Students</span>
                </div>
                {(<span class="np-rollover">{rollover_note}</span>)
                    if rollover_note
                    else None}
                <button class="np-signout" onClick={lambda { do_logout(); }}>
                    Sign out
                </button>
            </header>
            {(<div class="np-error">{error}</div>) if error else None}
            {(<div
                class="np-note"
                title="Click to dismiss"
                onClick={lambda { dismiss_note(); }}
            >
                {note}
            </div>) if note else None}

            <div class="np-stats">
                <span class="np-stat">
                    <strong>{count_due_soon()}</strong>
                    {buf_label()}
                </span>
                <span class="np-stat">
                    <strong>{count_week()}</strong> this week
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
                                "np-chip " + ("np-chip-on" if quick == q and not cal else "")
                            }
                            onClick={lambda {
                                quick = q;
                                cal = False;
                                special = "";
                            }}
                        >
                            {label}
                        </button>
                        for (q, label) in [
                            ("all", "All"),
                            ("today", "Today"),
                            ("week", "This week")
                        ]
                    ]}
                    <div class="np-side-title np-side-folders">
                        <span>Folders</span>
                        <button
                            class={"np-gear " + ("np-gear-on" if manage_f else "")}
                            title="Manage folders (reorder / delete)"
                            onClick={lambda { manage_f = not manage_f; }}
                        >
                            ⚙
                        </button>
                    </div>
                    {(<button
                        key="__all"
                        class={"np-chip " + ("np-chip-on" if not folder_filter else "")}
                        onClick={lambda { folder_filter = ""; special = ""; }}
                    >
                        All folders
                    </button>) if not manage_f else None}
                    {([
                        <button
                            key={f.name}
                            class={
                                "np-chip "
                                    + ("np-chip-on" if folder_filter == f.name else "")
                            }
                            onClick={lambda { folder_filter = f.name; special = ""; }}
                        >
                            {f.name}
                        </button>
                        for f in folders
                    ]) if not manage_f else [
                        <div class="np-mrow" key={f.name}>
                            <span class="np-mrow-name">{f.name}</span>
                            <button
                                class="np-marrow"
                                title="Move up"
                                onClick={lambda { do_move_folder(f.name, -1); }}
                            >
                                ↑
                            </button>
                            <button
                                class="np-marrow"
                                title="Move down"
                                onClick={lambda { do_move_folder(f.name, 1); }}
                            >
                                ↓
                            </button>
                            <button
                                class="np-mrow-x"
                                title="Delete folder (only if empty)"
                                onClick={lambda { do_delete_folder(f.name); }}
                            >
                                ✕
                            </button>
                        </div>
                        for f in folders
                    ]}
                    <div class="np-newfolder">
                        <input
                            value={new_folder_name}
                            onChange={lambda (e: ChangeEvent) {
                                new_folder_name = e.target.value;
                                folder_target = "";
                            }}
                            placeholder="+ new folder"
                        />
                        <button onClick={lambda { do_add_folder(); }}>Add</button>
                    </div>
                    {(<button
                        class={
                            "np-chip np-chip-done "
                                + ("np-chip-on" if special == "done" else "")
                        }
                        onClick={lambda {
                            special = "done";
                            folder_filter = "";
                        }}
                    >
                        Done
                    </button>) if count_done() > 0 else None}
                    {(<button
                        class={
                            "np-chip np-chip-del "
                                + ("np-chip-on" if special == "deleted" else "")
                        }
                        onClick={lambda {
                            special = "deleted";
                            folder_filter = "";
                        }}
                    >
                        Deleted
                    </button>) if len(trash) > 0 else None}
                </aside>

                <main class="np-main">
                    <div class="np-viewhead">
                        <span class="np-viewtitle">
                            {("Calendar" if cal else view_title())}
                        </span>
                        {(<span class="np-buf">
                            due within
                            <input
                                class="np-buf-num"
                                type="number"
                                min="0"
                                value={str(buf_days)}
                                onChange={lambda (e: ChangeEvent) {
                                    set_buf_days(e.target.value);
                                }}
                            />
                            <select
                                class="np-buf-unit"
                                value={buf_unit}
                                onChange={lambda (e: ChangeEvent) {
                                    buf_unit = e.target.value;
                                }}
                            >
                                <option value="days">
                                    {("day" if buf_days == 1 else "days")}
                                </option>
                                <option value="weeks">
                                    {("week" if buf_days == 1 else "weeks")}
                                </option>
                            </select>
                        </span>)
                            if quick == "today" and not cal
                            else None}
                        {(<span class="np-count">
                            {str(shown_count())
                                + " shown"
                                + (" · folder: " + folder_filter)
                                if folder_filter
                                else str(shown_count()) + " shown"}
                        </span>)
                            if not cal
                            else None}
                        <button class="np-calbtn" onClick={lambda { toggle_cal(); }}>
                            {("List" if cal else "Calendar")}
                        </button>
                    </div>

                    {(<div class="np-cal">
                        <div class="np-calhead">
                            <button
                                class="np-calnav"
                                onClick={lambda { cal_step(-1); }}
                            >
                                ‹
                            </button>
                            <span class="np-calmonth">
                                {MONTHS[cal_m - 1] + " " + str(cal_y)}
                            </span>
                            <button
                                class="np-calnav"
                                onClick={lambda { cal_step(1); }}
                            >
                                ›
                            </button>
                            {(<a
                                class="np-ics"
                                href={ics_url}
                                download="nudge.ics"
                            >
                                Download .ics
                            </a>)
                                if ics_url
                                else None}
                        </div>
                        <div class="np-calgrid np-calwd">
                            {[
                                <span key={w} class="np-cald">{w}</span>
                                for w in ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                            ]}
                        </div>
                        <div class="np-calgrid">{cal_grid()}</div>
                        <div class="np-callegend">
                            {[
                                <span key={k} class="np-legend">
                                    <span
                                        class="np-dot"
                                        style={{"backgroundColor": type_color(k)}}
                                    />
                                    {type_label(k)}
                                </span>
                                for k in ["exam", "quiz", "assignment", "project"]
                            ]}
                        </div>
                    </div>)
                        if cal
                        else <>
                            {(<div class="np-addcard">
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
                                        pick_new_folder(e.target.value);
                                    }}
                                >
                                    {[
                                        <option key={f.name} value={f.name}>{f.name}</option>
                                        for f in folders
                                    ]}
                                    <option value="__add__">+ add new folder…</option>
                                </select>
                                <button
                                    class="np-add-btn"
                                    onClick={lambda {
                                        if not busy { do_add(); }
                                    }}
                                >
                                    {("… adding" if busy == "add" else "Add")}
                                </button>
                                <button
                                    class="np-meta-toggle"
                                    onClick={lambda { show_meta = not show_meta; }}
                                >
                                    {("Less" if show_meta else "Details")}
                                </button>
                                {(<div class="np-add-meta">
                                    <select
                                        value={new_type}
                                        onChange={lambda (e: ChangeEvent) {
                                            pick_new_type(e.target.value);
                                        }}
                                    >
                                        <option value="">Type</option>
                                        <option value="exam">Exam</option>
                                        <option value="quiz">Quiz</option>
                                        <option value="assignment">Assignment</option>
                                        <option value="project">Project</option>
                                        {[
                                            <option key={t.name} value={t.name.lower()}>
                                                {t.name}
                                            </option>
                                            for t in custom_types()
                                        ]}
                                        <option value="__add__">+ add new type…</option>
                                    </select>
                                    {(<div class="np-newtype">
                                        <input
                                            value={new_type_name}
                                            onChange={lambda (e: ChangeEvent) {
                                                new_type_name = e.target.value;
                                            }}
                                            placeholder="New type name"
                                        />
                                        <button
                                            onClick={lambda {
                                                if not busy { do_create_type(); }
                                            }}
                                        >
                                            Add
                                        </button>
                                        <button
                                            class="np-newtype-x"
                                            onClick={lambda { cancel_new_type(); }}
                                        >
                                            Cancel
                                        </button>
                                    </div>) if type_target == "new" else None}
                                    <input
                                        value={new_location}
                                        onChange={lambda (e: ChangeEvent) {
                                            new_location = e.target.value;
                                        }}
                                        placeholder="Location (place / address)"
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
                                </div>) if show_meta else None}
                                {(<div class="np-newtype">
                                    <input
                                        value={new_folder_name}
                                        onChange={lambda (e: ChangeEvent) {
                                            new_folder_name = e.target.value;
                                        }}
                                        placeholder="New folder name"
                                    />
                                    <button
                                        onClick={lambda {
                                            if not busy { do_add_folder(); }
                                        }}
                                    >
                                        Add
                                    </button>
                                    <button
                                        class="np-newtype-x"
                                        onClick={lambda { cancel_new_folder(); }}
                                    >
                                        Cancel
                                    </button>
                                </div>) if folder_target == "new" else None}
                            </div>) if special != "deleted" else None}

                            {(<div class="np-trash">
                                {(<div class="np-empty">
                                    Nothing deleted in the past 30 days.
                                </div>) if len(trash) == 0
                                    else [
                                        <div class="np-task np-trash-row" key={jid(t)}>
                                            <div class="np-task-row">
                                                <span class="np-title np-done">
                                                    {t.title}
                                                </span>
                                                <span
                                                    class="np-badge"
                                                    style={{
                                                        "backgroundColor": folder_color(t.folder_name)
                                                    }}
                                                >
                                                    {t.folder_name}
                                                </span>
                                                <span class="np-due">{t.due_date}</span>
                                                <span class="np-trash-note">
                                                    deleted {t.deleted_at}
                                                </span>
                                                <button
                                                    class="np-restore"
                                                    title="Put it back"
                                                    onClick={lambda { do_restore(jid(t)); }}
                                                >
                                                    Restore
                                                </button>
                                            </div>
                                        </div>
                                        for t in trash
                                    ]}
                            </div>) if special == "deleted"
                                else ((<div class="np-empty">
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
                                                title="Show details"
                                                onClick={lambda { do_expand(jid(t)); }}
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
                                                        + ("np-due-today" if today and t.due_date <= ymd_add(today, buf_days) else "")
                                                }
                                            >
                                                {t.due_date}
                                            </span>
                                            <button
                                                class="np-caret"
                                                title="Details"
                                                onClick={lambda { do_expand(jid(t)); }}
                                            >
                                                {("▴" if expanded == jid(t) else "▾")}
                                            </button>
                                        </div>
                                        {(<div class="np-detail">
                                            <div class="np-meta">
                                                <select
                                                    class="np-type-sel"
                                                    style={{"backgroundColor": type_color(t.task_type)}}
                                                    title="Change type tag"
                                                    value={t.task_type}
                                                    onChange={lambda (e: ChangeEvent) {
                                                        pick_task_type(
                                                            jid(t),
                                                            t.folder_name,
                                                            e.target.value
                                                        );
                                                    }}
                                                >
                                                    <option value="">Type</option>
                                                    <option value="exam">Exam</option>
                                                    <option value="quiz">Quiz</option>
                                                    <option value="assignment">Assignment</option>
                                                    <option value="project">Project</option>
                                                    {[
                                                        <option key={c.name} value={c.name.lower()}>
                                                            {c.name}
                                                        </option>
                                                        for c in custom_types()
                                                    ]}
                                                    <option value="__add__">+ add new type…</option>
                                                </select>
                                                {(<span class="np-pri">P:high</span>)
                                                    if t.priority == "high"
                                                    else None}
                                                {(<span class="np-people">{t.people}</span>)
                                                    if t.people
                                                    else None}
                                                {(<a
                                                    class="np-room"
                                                    href={maps_href(t.location)}
                                                    target="_blank"
                                                    rel="noreferrer"
                                                    title="Open in Google Maps (travel time)"
                                                >
                                                    📍 {t.location}
                                                </a>)
                                                    if t.location
                                                    else None}
                                            </div>
                                            <div class="np-pick">
                                                <select
                                                    value={t.folder_name}
                                                    title="Move to another folder"
                                                    onChange={lambda (e: ChangeEvent) {
                                                        pick_task_folder(
                                                            jid(t),
                                                            t.task_type,
                                                            e.target.value
                                                        );
                                                    }}
                                                >
                                                    {[
                                                        <option key={f.name} value={f.name}>
                                                            {f.name}
                                                        </option>
                                                        for f in folders
                                                    ]}
                                                    <option value="__add__">
                                                        + add new folder…
                                                    </option>
                                                </select>
                                            </div>
                                            {(<div class="np-newtype">
                                                <input
                                                    value={new_folder_name}
                                                    onChange={lambda (e: ChangeEvent) {
                                                        new_folder_name = e.target.value;
                                                    }}
                                                    placeholder="New folder name"
                                                />
                                                <button
                                                    onClick={lambda {
                                                        if not busy { do_add_folder(); }
                                                    }}
                                                >
                                                    Add
                                                </button>
                                                <button
                                                    class="np-newtype-x"
                                                    onClick={lambda { cancel_new_folder(); }}
                                                >
                                                    Cancel
                                                </button>
                                            </div>) if folder_target == jid(t) else None}
                                            {(<div class="np-newtype">
                                                <input
                                                    value={new_type_name}
                                                    onChange={lambda (e: ChangeEvent) {
                                                        new_type_name = e.target.value;
                                                    }}
                                                    placeholder="New type name"
                                                />
                                                <button
                                                    onClick={lambda {
                                                        if not busy { do_create_type(); }
                                                    }}
                                                >
                                                    Add
                                                </button>
                                                <button
                                                    class="np-newtype-x"
                                                    onClick={lambda { cancel_new_type(); }}
                                                >
                                                    Cancel
                                                </button>
                                            </div>) if type_target == jid(t) else None}
                                            <div class="np-actions">
                                                <button
                                                    class="np-ai"
                                                    title="AI breakdown"
                                                    onClick={lambda {
                                                        if not busy {
                                                            do_breakdown(jid(t));
                                                        }
                                                    }}
                                                >
                                                    {("… thinking"
                                                        if busy == jid(t)
                                                        else "break down")}
                                                </button>
                                                <div class="np-caldrop">
                                                    <button
                                                        class="np-gcal"
                                                        title="Add to a calendar (Google or .ics)"
                                                        onClick={lambda {
                                                            toggle_cal_menu(jid(t));
                                                        }}
                                                    >
                                                        Calendar ▾
                                                    </button>
                                                    {(<div class="np-calmenu">
                                                        <a
                                                            href={gcal_href(t)}
                                                            target="_blank"
                                                            rel="noreferrer"
                                                            onClick={lambda { cal_menu = ""; }}
                                                        >
                                                            Google Calendar
                                                        </a>
                                                        {(<a
                                                            href={ics_one}
                                                            download="nudge-task.ics"
                                                            title="Apple / Mac Calendar and Outlook: download, then double-click to add"
                                                            onClick={lambda { cal_menu = ""; }}
                                                        >
                                                            .ics (Mac / any calendar)
                                                        </a>) if ics_one else None}
                                                    </div>) if cal_menu == jid(t) else None}
                                                </div>
                                                {(<button
                                                    class="np-invite"
                                                    title="Email an event invite to the collaborators"
                                                    onClick={lambda {
                                                        start_invite(jid(t), t.people);
                                                    }}
                                                >
                                                    ✉ invite
                                                </button>) if t.people else None}
                                                <button
                                                    class="np-del"
                                                    title="Delete task"
                                                    onClick={lambda { do_delete(jid(t)); }}
                                                >
                                                    ✕
                                                </button>
                                            </div>
                                            {(<div class="np-invite-panel">
                                                <div class="np-invite-head">
                                                    Send event invite?
                                                </div>
                                                <div class="np-invite-to">
                                                    To: {invite_to}
                                                </div>
                                                <div class="np-invite-sub">
                                                    The invite email carries the event details and a
                                                    calendar link. Nothing is sent until you press
                                                    Send.
                                                </div>
                                                <div class="np-invite-btns">
                                                    <button
                                                        class="np-invite-send"
                                                        onClick={lambda {
                                                            if not busy { do_invite(); }
                                                        }}
                                                    >
                                                        {("… sending"
                                                            if busy == "invite"
                                                            else "Send invite")}
                                                    </button>
                                                    <button
                                                        class="np-invite-cancel"
                                                        onClick={lambda {
                                                            invite_stage = "";
                                                            invite_for = "";
                                                            invite_to = "";
                                                        }}
                                                    >
                                                        Cancel
                                                    </button>
                                                </div>
                                            </div>)
                                                if invite_stage == "confirm"
                                                    and invite_for == jid(t)
                                                else None}
                                            {(<div class="np-ainote np-busy">
                                                AI is writing a breakdown -- about 15 seconds…
                                            </div>)
                                                if busy and busy == jid(t)
                                                else None}
                                            <div class="np-subs">
                                                {(<span class="np-sub-hint">
                                                    No steps yet -- hit "break down"
                                                </span>) if len(task_subs(jid(t))) == 0
                                                    else [
                                                            {(<div
                                                                class="np-sub-edit"
                                                                key={jid(s)}
                                                            >
                                                                <input
                                                                    class="np-ed-title"
                                                                    value={ed_sub_title}
                                                                    onChange={lambda (e: ChangeEvent) {
                                                                        ed_sub_title = e.target.value;
                                                                    }}
                                                                />                                        <input
                                            type="date"
                                            class="np-ed-due"
                                            value={ed_sub_due}
                                            onChange={lambda (e: ChangeEvent) {
                                                ed_sub_due = e.target.value;
                                            }}
                                        />
                                        <input
                                            type="number"
                                            min="1"
                                            class="np-ed-est"
                                            value={ed_sub_est}
                                            title="Estimated minutes to complete"
                                            onChange={lambda (e: ChangeEvent) {
                                                ed_sub_est = e.target.value;
                                            }}
                                        />
                                        <span class="np-ed-unit">min</span>
                                        <button
                                            class="np-ed-save"
                                                                    onClick={lambda {
                                                                        do_save_sub(jid(s));
                                                                    }}
                                                                >
                                                                    Save
                                                                </button>
                                                                <button
                                                                    class="np-ed-cancel"
                                                                    onClick={lambda {
                                                                        editing_sub = "";
                                                                    }}
                                                                >
                                                                    Cancel
                                                                </button>
                                                            </div>) if editing_sub == jid(s)
                                                                else <div class="np-sub" key={jid(s)}>
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
                                                                    <button
                                                                        class="np-sub-pen"
                                                                        title="Edit step"
                                                                        onClick={lambda {
                                                                            start_edit_sub(s);
                                                                        }}
                                                                    >
                                                                        ✎
                                                                    </button>
                                                                    <button
                                                                        class="np-sub-x"
                                                                        title="Delete step"
                                                                        onClick={lambda {
                                                                            do_delete_sub(jid(s));
                                                                        }}
                                                                    >
                                                                        ✕
                                                                    </button>
                                                                </div>}
                                                        for s in task_subs(jid(t))
                                                    ]}
                                            </div>
                                        </div>)
                                            if expanded == jid(t)
                                            else None}
                                    </div>
                                    for t in visible_tasks()
                                ])}
                        </>}
                </main>
            </div>

            <footer class="np-footer">
                One core, two surfaces -- this page and the CLI read and
                write the same planner graph.
                <br />
                CLI: <code>jac run cli -- today</code>
                &nbsp;|&nbsp; <code>jac run cli -- add "..."</code>
                &nbsp;|&nbsp; <code>jac run cli -- breakdown &lt;task&gt;</code>
            </footer>
        </div>;
}
