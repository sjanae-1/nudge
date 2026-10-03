"""Nudge -- sign in / create account page."""

import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, Navigate }

def:pub Login -> JsxPage {
    has email: str = "",
        pw: str = "",
        mode: str = "login",
        err: str = "",
        busy: bool = False,
        done: bool = False;

    async def submit {
        err = "";
        if not email.strip() or not pw {
            err = "Email and password are required";
            return;
        }
        busy = True;
        # Pre-declare every var that holds an `await` result (see jac-cl-auth).
        ok: bool = False;
        res: SignupResult | None = None;
        try {
            if mode == "signup" {
                res = await jacSignup(email.strip(), pw);
                if not res.success {
                    err = res.error or "sign-up failed (email may already be taken)";
                    return;
                }
            }
            ok = await jacLogin(email.strip(), pw);
            if not ok {
                err = "invalid credentials";
                return;
            }
            done = True;
        } except Exception as e {
            err = str(e);
        } finally {
            busy = False;
        }
    }

    if done {
        return <Navigate to="/" replace={True} />;
    }

    return
        <div class="np-auth">
            <div class="np-auth-card">
                <h1>Nudge</h1>
                <span class="np-tagline">
                    Personal Planning App built for College Students
                </span>

                <div class="np-auth-tabs">
                    <button
                        class={"np-auth-tab " + ("np-auth-tab-on" if mode == "login" else "")}
                        onClick={lambda { mode = "login"; err = ""; }}
                    >
                        Sign in
                    </button>
                    <button
                        class={"np-auth-tab " + ("np-auth-tab-on" if mode == "signup" else "")}
                        onClick={lambda { mode = "signup"; err = ""; }}
                    >
                        Create account
                    </button>
                </div>

                {(<div class="np-error">{err}</div>) if err else None}

                <input
                    class="np-auth-input"
                    type="email"
                    placeholder="Email"
                    value={email}
                    onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                    onKeyPress={lambda (e: KeyboardEvent) {
                        if e.key == "Enter" { submit(); }
                    }}
                />
                <input
                    class="np-auth-input"
                    type="password"
                    placeholder="Password"
                    value={pw}
                    onChange={lambda (e: ChangeEvent) { pw = e.target.value; }}
                    onKeyPress={lambda (e: KeyboardEvent) {
                        if e.key == "Enter" { submit(); }
                    }}
                />

                <button
                    class="np-auth-btn"
                    onClick={lambda {
                        if not busy { submit(); }
                    }}
                >
                    {("…" if busy
                        else ("Create account" if mode == "signup" else "Sign in"))}
                </button>

                <p class="np-auth-hint">
                    {("Already have an account? Pick Sign in."
                        if mode == "signup"
                        else "New here? Create an account -- your planner stays private to you.")}
                </p>
            </div>
        </div>;
}
