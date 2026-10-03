"""Nudge mobile -- the React Native (mobUI) face of the planner.

Four-interface requirement: the web app, CLI, and this mobile app all
bridge to the same protected core.api endpoints, so a task added on the
phone shows up in the browser and the terminal (and vice versa) -- the
server persists every plan between sessions.

    jac run --dev --platform web mobile   # browser preview (react-native-web)
    jac run --dev mobile                  # Metro + Expo Go QR
    jac build mobile --platform android   # native build
"""

import from "@jac/mobui" {
    View,
    Text,
    ScrollView,
    Pressable,
    TextInput,
    Switch,
    ActivityIndicator,
    StyleSheet
}

import from "@jac/runtime" {
    SignupResult,
    jacLogin,
    jacSignup,
    jacLogout,
    jacIsLoggedIn
}

import from core.api {
    current_date,
    list_folders,
    list_tasks,
    add_task,
    complete_task
}

# --- Pure date helpers (integer math only -- no datetime lib client-side) ---

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

"""True when a bridge failure means the session token is dead (stale
account / reset store) -- the UI should sign out, not show raw JSON."""
def is_auth_error(msg: str) -> bool {
    return (
        "UNAUTHORIZED" in msg
        or "unknown user" in msg
        or "IDENTITY_" in msg
    );
}

glob styles = StyleSheet.create({
    "screen": {"flex": 1, "backgroundColor": "#f4f5fb"},
    "body": {"padding": 16, "paddingTop": 56, "gap": 14, "paddingBottom": 40},
    "center": {"flex": 1, "justifyContent": "center", "alignItems": "center", "backgroundColor": "#f4f5fb"},
    "authWrap": {"padding": 24, "paddingTop": 90, "gap": 18, "alignItems": "center"},
    "header": {"flexDirection": "row", "alignItems": "center", "justifyContent": "space-between"},
    "brand": {"fontSize": 28, "fontWeight": "bold", "color": "#171a2b", "letterSpacing": -0.5},
    "tagline": {"fontSize": 13, "color": "#7a7f99", "fontStyle": "italic"},
    "stats": {"fontSize": 13, "color": "#7b8098", "fontWeight": "600"},
    "statNum": {"color": "#171a2b", "fontWeight": "800"},
    "statDone": {"color": "#16a34a", "fontWeight": "800"},
    "card": {
        "backgroundColor": "#ffffff",
        "borderRadius": 16,
        "padding": 14,
        "gap": 10,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "shadowColor": "#000",
        "shadowOpacity": 0.05,
        "shadowRadius": 8,
        "shadowOffset": {"width": 0, "height": 3}
    },
    "input": {
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "borderRadius": 10,
        "paddingVertical": 10,
        "paddingHorizontal": 12,
        "fontSize": 15,
        "color": "#171a2b",
        "backgroundColor": "#ffffff"
    },
    "dueInput": {
        "flex": 1,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "borderRadius": 10,
        "paddingVertical": 10,
        "paddingHorizontal": 12,
        "fontSize": 15,
        "color": "#171a2b",
        "backgroundColor": "#ffffff"
    },
    "primary": {
        "backgroundColor": "#16a34a",
        "borderRadius": 10,
        "paddingVertical": 11,
        "paddingHorizontal": 18,
        "alignItems": "center"
    },
    "primaryText": {"color": "#ffffff", "fontSize": 15, "fontWeight": "bold"},
    "authBtn": {
        "backgroundColor": "#636efa",
        "borderRadius": 10,
        "paddingVertical": 11,
        "paddingHorizontal": 18,
        "alignItems": "center"
    },
    "link": {"color": "#4f46e5", "fontSize": 14, "textAlign": "center", "fontWeight": "600"},
    "err": {"color": "#dc2626", "fontSize": 13, "textAlign": "center"},
    "chipRow": {"gap": 8, "paddingVertical": 2},
    "chip": {
        "borderRadius": 999,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "backgroundColor": "#f3f4fa",
        "paddingVertical": 6,
        "paddingHorizontal": 12
    },
    "chipOn": {
        "borderRadius": 999,
        "borderWidth": 1,
        "borderColor": "#4f46e5",
        "backgroundColor": "#4f46e5",
        "paddingVertical": 6,
        "paddingHorizontal": 12
    },
    "chipText": {"fontSize": 13, "color": "#171a2b", "fontWeight": "500"},
    "chipTextOn": {"fontSize": 13, "color": "#ffffff", "fontWeight": "600"},
    "section": {"fontSize": 12, "fontWeight": "bold", "color": "#171a2b", "textTransform": "uppercase", "marginTop": 6},
    "row": {
        "flexDirection": "row",
        "alignItems": "center",
        "gap": 10,
        "backgroundColor": "#ffffff",
        "borderRadius": 12,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "paddingVertical": 10,
        "paddingHorizontal": 12
    },
    "rowMain": {"flex": 1, "gap": 3},
    "rowTitle": {"fontSize": 15, "color": "#171a2b", "fontWeight": "600"},
    "rowTitleDone": {"fontSize": 15, "color": "#9aa0b5", "fontWeight": "600", "textDecorationLine": "line-through"},
    "rowMeta": {"fontSize": 12, "color": "#7b8098"},
    "metaRow": {"flexDirection": "row", "alignItems": "center", "gap": 6, "flexWrap": "wrap"},
    "badgeText": {"fontSize": 11, "color": "#ffffff", "fontWeight": "700"},
    "loc": {"fontSize": 12, "color": "#7b8098"},
    "recur": {
        "fontSize": 12,
        "color": "#5b3fd6",
        "backgroundColor": "#f4f0ff",
        "borderWidth": 1,
        "borderColor": "#e3daff",
        "borderRadius": 999,
        "paddingVertical": 2,
        "paddingHorizontal": 8,
        "fontWeight": "600",
        "overflow": "hidden"
    },
    "ctrlRow": {"flexDirection": "row", "flexWrap": "wrap", "alignItems": "center", "gap": 8},
    "timeRow": {"flexDirection": "row", "gap": 8, "flex": 1, "minWidth": 160},
    "timeInput": {
        "flex": 1,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "borderRadius": 10,
        "paddingVertical": 8,
        "paddingHorizontal": 10,
        "fontSize": 14,
        "color": "#171a2b",
        "backgroundColor": "#ffffff"
    },
    "untilInput": {
        "flex": 1,
        "minWidth": 170,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "borderRadius": 10,
        "paddingVertical": 8,
        "paddingHorizontal": 10,
        "fontSize": 14,
        "color": "#171a2b",
        "backgroundColor": "#ffffff"
    },
    "empty": {"fontSize": 14, "color": "#7a7f99", "fontStyle": "italic", "paddingVertical": 8},
    "signout": {
        "borderRadius": 999,
        "borderWidth": 1,
        "borderColor": "#e7e9f2",
        "backgroundColor": "#ffffff",
        "paddingVertical": 7,
        "paddingHorizontal": 14
    },
    "signoutText": {"color": "#4f46e5", "fontSize": 13, "fontWeight": "bold"}
});

def:pub app -> JsxElement {
    has auth_email: str = "",
        auth_pw: str = "",
        auth_mode: str = "login",
        auth_err: str = "",
        auth_busy: bool = False,
        loading: bool = True,
        busy: bool = False,
        error: str = "",
        today: str = "",
        tasks: list[any] = [],
        folders: list[any] = [],
        new_title: str = "",
        new_due: str = "",
        new_folder: str = "",
        new_recur: str = "",
        new_start: str = "13:00",
        new_end: str = "15:00",
        new_until: str = "";

    """Pull today + folders from the shared server (bridged, protected)."""
    async def load {
        d: str = "";
        fs: list[any] = [];
        ts: list[any] = [];
        try {
            d = await current_date();
            today = d;
            fs = await list_folders();
            folders = fs;
            ts = await list_tasks();
            tasks = ts;
            if not new_due.strip() {
                new_due = today;
            }
            if not new_folder.strip() and len(folders) > 0 {
                new_folder = folders[0].name;
            }
            error = "";
        } except Exception as e {
            if is_auth_error(str(e)) {
                # Stale/dead session token: sign out cleanly instead of
                # surfacing the raw bridge error banner.
                jacLogout();
            } else {
                error = str(e);
            }
        } finally {
            loading = False;
            busy = False;
        }
    }

    async def refresh {
        ts: list[any] = [];
        try {
            ts = await list_tasks();
            tasks = ts;
        } except Exception as e {
            error = str(e);
        }
    }

    async can with entry {
        if jacIsLoggedIn() {
            await load();
        } else {
            loading = False;
        }
    }

    async def submit {
        auth_err = "";
        if not auth_email.strip() or not auth_pw {
            auth_err = "Email and password are required";
            return;
        }
        auth_busy = True;
        signup_result: SignupResult | None = None;
        ok: bool = False;
        try {
            if auth_mode == "signup" {
                signup_result = await jacSignup(auth_email.strip(), auth_pw);
                if not signup_result.success {
                    auth_err = (
                        signup_result.error or "sign-up failed (email may be taken)"
                    );
                    return;
                }
            }
            ok = await jacLogin(auth_email.strip(), auth_pw);
            if not ok {
                auth_err = "invalid credentials";
                return;
            }
            loading = True;
            await load();
        } except Exception as e {
            auth_err = str(e);
        } finally {
            auth_busy = False;
        }
    }

    def logout {
        jacLogout();
        tasks = [];
        folders = [];
        loading = False;
    }

    async def do_add {
        error = "";
        if not new_title.strip() {
            error = "Give the task a title";
            return;
        }
        if len(new_due) != 10 {
            error = "Due date must be yyyy-mm-dd";
            return;
        }
        busy = True;
        try {
            await add_task(
                title=new_title.strip(),
                due_date=new_due.strip(),
                folder_name=new_folder,
                recurrence=new_recur,
                until=(new_until if new_recur else ""),
                start_time=(new_start if new_recur else ""),
                end_time=(new_end if new_recur else "")
            );
            new_title = "";
            new_recur = "";
            new_until = "";
            await refresh();
        } except Exception as e {
            error = str(e);
        } finally {
            busy = False;
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

    def today_tasks -> list[any] {
        out: list[any] = [];
        if not today {
            return out;
        }
        for t in tasks {
            if t.due_date <= today {
                out.append(t);
            }
        }
        return out;
    }

    def week_tasks -> list[any] {
        out: list[any] = [];
        if not today {
            return out;
        }
        cutoff = ymd_add(today, 7);
        for t in tasks {
            if t.due_date > today and t.due_date <= cutoff {
                out.append(t);
            }
        }
        return out;
    }

    def count_today -> int {
        if not today {
            return 0;
        }
        n = 0;
        for t in tasks {
            if not t.completed and t.due_date <= today {
                n = n + 1;
            }
        }
        return n;
    }

    def count_week -> int {
        if not today {
            return 0;
        }
        n = 0;
        cutoff = ymd_add(today, 7);
        for t in tasks {
            if not t.completed and t.due_date > today and t.due_date <= cutoff {
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

    def fcolor(name: str) -> str {
        for f in folders {
            if f.name == name {
                return f.color;
            }
        }
        return "#9e9e9e";
    }

    # --- Not signed in: email + password screen ---
    if not jacIsLoggedIn() {
        return
            <ScrollView style={styles.screen} contentContainerStyle={styles.authWrap}>
                <Text style={styles.brand}>
                    <Text style={{"color": "#171a2b"}}>N</Text><Text style={{"color": "#252559"}}>u</Text><Text style={{"color": "#333088"}}>d</Text><Text style={{"color": "#413ab7"}}>g</Text><Text style={{"color": "#4f46e5"}}>e</Text>
                </Text>
                <Text style={styles.tagline}>
                    Personal Planning App built for College Students
                </Text>
                <View style={styles.card}>
                    <TextInput
                        style={styles.input}
                        value={auth_email}
                        placeholder="Email"
                        placeholderTextColor="#8a93a6"
                        autoCapitalize="none"
                        keyboardType="email-address"
                        onChangeText={lambda (t: str) { auth_email = t; }}
                    />
                    <TextInput
                        style={styles.input}
                        value={auth_pw}
                        placeholder="Password"
                        placeholderTextColor="#8a93a6"
                        secureTextEntry={True}
                        onChangeText={lambda (t: str) { auth_pw = t; }}
                    />
                    {(<Text style={styles.err}>{auth_err}</Text>)
                        if auth_err
                        else <View/>}
                    <Pressable
                        style={styles.authBtn}
                        onPress={lambda {
                            if not auth_busy { submit(); }
                        }}
                    >
                        <Text style={styles.primaryText}>
                            {("… signing in"
                                if auth_busy
                                else ("Sign in"
                                    if auth_mode == "login"
                                    else "Create account"))}
                        </Text>
                    </Pressable>
                    <Pressable
                        onPress={lambda {
                            auth_mode = (
                                "signup" if auth_mode == "login" else "login"
                            );
                            auth_err = "";
                        }}
                    >
                        <Text style={styles.link}>
                            {("New here? Create an account"
                                if auth_mode == "login"
                                else "Have an account? Sign in")}
                        </Text>
                    </Pressable>
                </View>
            </ScrollView>;
    }

    if loading {
        return
            <View style={styles.center}>
                <ActivityIndicator size="large" color="#16a34a"/>
            </View>;
    }

    return
        <ScrollView
            style={styles.screen}
            contentContainerStyle={styles.body}
            keyboardShouldPersistTaps="handled"
        >
            <View style={styles.header}>
                <View>
                    <Text style={styles.brand}>
                        <Text style={{"color": "#171a2b"}}>N</Text><Text style={{"color": "#252559"}}>u</Text><Text style={{"color": "#333088"}}>d</Text><Text style={{"color": "#413ab7"}}>g</Text><Text style={{"color": "#4f46e5"}}>e</Text>
                    </Text>
                    <Text style={styles.tagline}>Personal Planning App built for College Students</Text>
                </View>
                <Pressable style={styles.signout} onPress={lambda { logout(); }}>
                    <Text style={styles.signoutText}>Sign out</Text>
                </Pressable>
            </View>

            <Text style={styles.stats}>
                {str(count_today())
                    + " due today  ·  "
                    + str(count_week())
                    + " this week  ·  "
                    + str(count_done())
                    + " done"}
            </Text>

            {(<Text style={styles.err}>{error}</Text>) if error else <View/>}

            <View style={styles.card}>
                <TextInput
                    style={styles.input}
                    value={new_title}
                    placeholder="What needs doing?"
                    placeholderTextColor="#8a93a6"
                    onChangeText={lambda (t: str) { new_title = t; }}
                />
                <View style={{"flexDirection": "row", "gap": 8}}>
                    <TextInput
                        style={styles.dueInput}
                        value={new_due}
                        placeholder="YYYY-MM-DD"
                        placeholderTextColor="#8a93a6"
                        autoCapitalize="none"
                        onChangeText={lambda (t: str) { new_due = t; }}
                    />
                    <Pressable
                        style={styles.primary}
                        onPress={lambda {
                            if not busy { do_add(); }
                        }}
                    >
                        <Text style={styles.primaryText}>
                            {("… adding" if busy else "Add")}
                        </Text>
                    </Pressable>
                </View>
                <ScrollView
                    horizontal={True}
                    showsHorizontalScrollIndicator={False}
                    contentContainerStyle={styles.chipRow}
                >
                    {[
                        <Pressable
                            key={f.name}
                            style={styles.chipOn if new_folder == f.name else styles.chip}
                            onPress={lambda { new_folder = f.name; }}
                        >
                            <Text
                                style={
                                    styles.chipTextOn
                                        if new_folder == f.name
                                        else styles.chipText
                                }
                            >
                                {f.name}
                            </Text>
                        </Pressable>
                        for f in folders
                    ]}
                </ScrollView>
                <View style={styles.ctrlRow}>
                    <Pressable
                        style={
                            styles.chipOn
                                if new_recur == "weekly"
                                else styles.chip
                        }
                        onPress={lambda {
                            new_recur = (
                                "" if new_recur == "weekly" else "weekly"
                            );
                        }}
                    >
                        <Text
                            style={
                                styles.chipTextOn
                                    if new_recur == "weekly"
                                    else styles.chipText
                            }
                        >
                            {"↻ Weekly"}
                        </Text>
                    </Pressable>
                    {(<View style={styles.timeRow}>
                        <TextInput
                            style={styles.timeInput}
                            value={new_start}
                            placeholder="starts 13:00"
                            placeholderTextColor="#8a93a6"
                            onChangeText={lambda (t: str) { new_start = t; }}
                        />
                        <TextInput
                            style={styles.timeInput}
                            value={new_end}
                            placeholder="ends 15:00"
                            placeholderTextColor="#8a93a6"
                            onChangeText={lambda (t: str) { new_end = t; }}
                        />
                    </View>) if new_recur == "weekly" else <View/>}
                    {(<TextInput
                        style={styles.untilInput}
                        value={new_until}
                        placeholder="stops yyyy-mm-dd (optional)"
                        placeholderTextColor="#8a93a6"
                        onChangeText={lambda (t: str) { new_until = t; }}
                    />) if new_recur == "weekly" else <View/>}
                </View>
            </View>

            <Text style={styles.section}>Today</Text>
            {([
                <View key={jid(t)} style={styles.row}>
                    <Switch
                        value={t.completed}
                        trackColor={{"false": "#e7e9f2", "true": "#16a34a"}}
                        onValueChange={lambda (v: bool) { do_toggle(jid(t)); }}
                    />
                    <View style={styles.rowMain}>
                        <Text
                            style={
                                styles.rowTitleDone
                                    if t.completed
                                    else styles.rowTitle
                            }
                            numberOfLines={2}
                        >
                            {t.title}
                        </Text>
                        <View style={styles.metaRow}>
                            <View
                                style={{
                                    "backgroundColor": fcolor(t.folder_name),
                                    "borderRadius": 999,
                                    "paddingVertical": 2,
                                    "paddingHorizontal": 8
                                }}
                            >
                                <Text style={styles.badgeText}>
                                    {t.folder_name}
                                </Text>
                            </View>
                            <Text style={styles.rowMeta}>
                                {"due " + t.due_date}
                            </Text>
                        </View>
                        {(<Text style={styles.loc}>
                            {"📍 " + t.location}
                        </Text>) if t.location else <View/>}
                    </View>
                </View>
                for t in today_tasks()
            ]) if len(today_tasks()) > 0
                else <Text style={styles.empty}>
                    Nothing due today -- add a task above.
                </Text>}

            <Text style={styles.section}>This week</Text>
            {([
                <View key={jid(t)} style={styles.row}>
                    <Switch
                        value={t.completed}
                        trackColor={{"false": "#e7e9f2", "true": "#16a34a"}}
                        onValueChange={lambda (v: bool) { do_toggle(jid(t)); }}
                    />
                    <View style={styles.rowMain}>
                        <Text
                            style={
                                styles.rowTitleDone
                                    if t.completed
                                    else styles.rowTitle
                            }
                            numberOfLines={2}
                        >
                            {t.title}
                        </Text>
                        <View style={styles.metaRow}>
                            <View
                                style={{
                                    "backgroundColor": fcolor(t.folder_name),
                                    "borderRadius": 999,
                                    "paddingVertical": 2,
                                    "paddingHorizontal": 8
                                }}
                            >
                                <Text style={styles.badgeText}>
                                    {t.folder_name}
                                </Text>
                            </View>
                            <Text style={styles.rowMeta}>
                                {"due " + t.due_date}
                            </Text>
                        </View>
                        {(<Text style={styles.loc}>
                            {"📍 " + t.location}
                        </Text>) if t.location else <View/>}
                    </View>
                </View>
                for t in week_tasks()
            ]) if len(week_tasks()) > 0
                else <Text style={styles.empty}>
                    Nothing else this week.
                </Text>}
        </ScrollView>;
}
