"""Nudge data model -- graph nodes shared by web, mobile, and CLI.

Folders hang off root; tasks hang off their folder; subtasks hang off
their task. Due dates are ISO strings (yyyy-mm-dd) so lexicographic
comparison is chronological -- that is what powers auto-rollover.
"""

node Folder {
    has name: str,
        color: str = "#6c8ebf",
        pos: int = 0;
}

"""User-defined task type (built-in types live client-side)."""
node TypeTag {
    has name: str,
        color: str = "#6c8ebf";
}

node Task {
    has title: str,
        due_date: str,
        completed: bool = False,
        folder_name: str = "Miscellaneous",
        people: str = "",
        location: str = "",
        priority: str = "medium",
        task_type: str = "",
        created_at: str = "",
        ai_note: str = "",
        deleted_at: str = "",
        recurrence: str = "",
        start_time: str = "",
        end_time: str = "";
}

node Subtask {
    has title: str,
        task_id: str = "",
        est_minutes: int = 30,
        due_date: str = "",
        completed: bool = False;
}
