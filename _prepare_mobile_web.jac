import from pathlib { Path }
import from jaclang.runtime.runtime { JacRuntime as Jac }
import from jaclang.client.targets.client_dev_common { prepare_vite_dev_compilation }

# One-shot: compile the mobile client modules (web flavor) so the dev
# server's /mobile/compiled/_entry.js resolves. Used for the mobile web
# preview; the generic serve path skips this step.
with entry:__main__ {
    project_dir = Path.cwd();
    entry_file = project_dir / "mobile" / "main.jac";
    Jac.set_full_target_path(str(entry_file));
    out = prepare_vite_dev_compilation(project_dir, entry_file);
    print("client compile done");
}
