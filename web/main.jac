"""Nudge -- web entry point (file-based router wrapper).

Routes live in `pages/`:
  pages/login.jac        -> /login        (sign in / create account)
  pages/(auth)/index.jac -> /             (the planner, auth-guarded)

This module only provides the router wrapper and the global stylesheet.
"""

import "./styles.css";

def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
