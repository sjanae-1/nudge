"""Nudge data model -- graph nodes shared by web, mobile, and CLI.

Folders hang off root; tasks hang off their folder; subtasks hang off
their task. Due dates are ISO strings (yyyy-mm-dd) so lexicographic
comparison is chronological -- that is what powers auto-rollover.

A recurring task is one occurrence per row: `series` links every
occurrence of the same repeat rule (empty = its own series),
`spawned_from` points at the occurrence that added it, and `until` is
the optional "repeat until" stop date (empty = repeats indefinitely).
`rolled_from` remembers the date an overdue task carried before
auto-rollover nudged it forward (empty = never nudged).
"""

"""Declared class-name history -- why every node needs a `__jac_schema__`.

The same source file gets two module names depending on which app loads
it: the `api` service namespaces app modules as
`_jac_app_<sha256(abs path of core/api.jac)>`, while the CLI colocates
`core.api` un-namespaced (`core.models`). Rows record the writer's
spelling in `archetype.__module__`, and the deserializer refuses a key
that is neither registered nor resolvable in this process -- so without
declaring the other spelling here, the web API drops every folder/task
the CLI wrote and the CLI drops every folder/task the API wrote.
Both names alias to this process's class object.
"""
def schema_was_both(cls_name: str) -> None {
    schema_was("core.models." + cls_name);
    api_fqn = api_service_fqn(cls_name);
    if api_fqn {
        schema_was(api_fqn);
    }
}

"""`<api-ns>.core.models.<cls_name>` -- mirrors application_namespace()."""
def api_service_fqn(cls_name: str) -> str {
    try {
        import os;
        import from hashlib { sha256 }
        import from jaclang.project.config { get_config }
        cfg = get_config();
        if cfg is not None {
            entry_path = os.path.join(str(cfg.project_root), "core", "api.jac");
            ns = "_jac_app_" + sha256(entry_path.encode("utf-8")).hexdigest()[:16];
            return ns + ".core.models." + cls_name;
        }
    } except Exception {}
    return "";
}

node Folder {
    has name: str,
        color: str = "#6c8ebf",
        pos: int = 0;

    static def __jac_schema__ -> None {
        schema_was_both("Folder");
    }
}

"""User-defined task type (built-in types live client-side)."""
node TypeTag {
    has name: str,
        color: str = "#6c8ebf";

    static def __jac_schema__ -> None {
        schema_was_both("TypeTag");
    }
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
        until: str = "",
        series: str = "",
        spawned_from: str = "",
        rolled_from: str = "",
        start_time: str = "",
        end_time: str = "";

    static def __jac_schema__ -> None {
        schema_was_both("Task");
    }
}

node Subtask {
    has title: str,
        task_id: str = "",
        est_minutes: int = 30,
        due_date: str = "",
        completed: bool = False;

    static def __jac_schema__ -> None {
        schema_was_both("Subtask");
    }
}
