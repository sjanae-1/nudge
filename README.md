# Nudge — Personal Planner in Jac

**Name:** Jiayin (Janae) Shao · **Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner for college students written in Jac.
Change a due date anywhere and it updates everywhere. Its three main features:

1. **AI Task Decomposition** — one click splits an overwhelming task into
   dated, editable 15–45-minute micro-steps. Every new account ships with a
   finished example already broken down under *Grocery shopping*.
2. **Auto-Rollover + Nudge** — unfinished overdue tasks automatically shift
   to today on load, keep a red `was <date>` marker, and offer a one-click
   **→ tomorrow** push.
3. **Recurring Tasks** — keep daily/weekly/monthly tasks on your radar until a stop date that ends the series.

## Setup & Run

**Prerequisites:** Python 3.10+ and `pip install jaclang==0.37.23`.
No AI API key needed, the local model (`local:qwen3.5-4b`) downloads
automatically on first run.

```bash
git clone https://github.com/sjanae-1/nudge.git
cd nudge
jac run --dev          # web app + API → http://localhost:8000 (API on :8001)
```

Pick **Create account** on the login page to register for a new account.

## CLI

```bash
jac run cli -- today                    # what is due soon
jac run cli -- all                      # every open task
jac run cli -- add "EECS 449 HW1" --due 2026-10-05 --folder "EECS 449" --priority high
jac run cli -- add "Team catchup" --due 2026-10-04 --recur weekly --until 2026-12-11
jac run cli -- breakdown <task>         # AI micro-steps
jac run cli -- done <task_id>
```

The CLI runs the API colocated in-process, so it hits the same database even
when the web server is off.

## Mobile App

```bash
# stop the web dev server first — both claim the 800x ports
jac run --dev --platform web mobile     # preview in a browser (react-native-web)
jac run --dev mobile                    # native: scan the Expo Go QR (press i / a)
```

First native run scaffolds the Expo project and installs npm deps (one-time).
A lightweight Today / This-week view for quick capture and completion on the go.

## How the four components fit together

```
              ┌────────────────────────────────────┐
              │  Server core/ — one graph DB, AI,  │
              │  rollover, calendar export         │
              └────────────────┬───────────────────┘
                    ┌──────────┼──────────┐
                    ▼          ▼          ▼
                  Web       Mobile       CLI
```

The server (`core/api.jac`, declared `service` app) is the single brain; the
web, mobile, and CLI are thin clients over it with the same JWT auth. The web
bridges over HTTP, the mobile app speaks the same bridge from React Native,
and the CLI registers the service locally to run in-process. Sign in on any
surface and all four stay in sync.

Three things that make it impressive:

1. **One brain, four surfaces** — a single declared service app and graph DB
   serve a full React dashboard, a React Native app, and an offline-capable
   CLI, with identical auth and zero data duplication.
2. **Color-aware calendar with scoped export** — folder chips filter both the
   calendar grid *and* the `.ics` download (the file contains only the
   selected folders), plus one-click Google Calendar / Apple `.ics` links per
   task.
3. **Safe by default** — completing moves tasks to a Done folder, deleting
   soft-deletes into a 30-day restorable Deleted folder, and lists re-sort
   live by due date → priority → start time → title.
