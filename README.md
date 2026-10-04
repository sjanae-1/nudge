# Nudge — Personal Planner in Jac

**Name:** Jiayin (Janae) Shao

**Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner for college students written in Jac.
With components of web frontend, mobile app, and terminal CLI, change a due date anywhere and it updates everywhere. Its three main features:

1. **List & Calendar views with a downloadable calendar** — see every task
   as a list or a month calendar, with a dynamic **"due within [N]
   [days/weeks]"** window on the "Today" view to keep the most urgent tasks on your radar.
2. **AI Task Breakdown** — one click splits an overwhelming task into
   dated, editable 15–45-minute subtasks. Every new account ships with a
   finished example already broken down under *Grocery shopping*.
3. **Done & Deleted folders with an Auto-Rollover nudge** — "Done" and "Delete" folders keep old tasks, each restorable with one click. Unfinished
   past-due tasks are moved to today, and a banner reports how many were
   nudged.

## Setup & Run

**Prerequisites:** Python 3.10+ and `pip install jaclang==0.37.23`.

```bash
git clone https://github.com/sjanae-1/nudge.git
cd nudge
jac run --dev          # web app + API → http://localhost:8000 (API on :8001)
```

Click on **Create account** on the login page to register for a new account.

## CLI

```bash
jac run cli -- login <username>         # sign in: CLI then shows YOUR web tasks
jac run cli -- logout                   # back to the shared anonymous list
jac run cli -- today                    # what is due soon
jac run cli -- all                      # every open task
jac run cli -- add "EECS 449 HW1" --due 2026-10-05 --folder "EECS 449" --priority high
jac run cli -- add "Team catchup" --due 2026-10-04 --recur weekly --until 2026-12-11
jac run cli -- breakdown <task>         # AI micro-steps
jac run cli -- done <task>              # task number or title fragment
jac run cli -- delete <task>            # move a task to the Delete folder
```

The CLI runs the API colocated in-process, so it hits the same database even
when the web server is off. Each account has its own task graph: run `login`
with the same username you use in the browser and `all` will list exactly
what the web app shows.

## Mobile App

```bash
# stop the web dev server first — both claim the 800x ports
jac run _prepare_mobile_web.jac         # one-shot: compile the mobile client for the browser preview
jac run --dev --platform web mobile     # preview in a browser (react-native-web)
jac run --dev mobile                    # native: scan the Expo Go QR (press i / a)
```

The one-shot prepare step is required on a fresh clone (and again after
`jac clean`): it writes `.jac/client/mobile/compiled/`, which the dev
server's index.html imports.

First native run scaffolds the Expo project and installs npm deps (one-time).
A lightweight Today / This-week view for quick capture and completion on the go.

## How the four components fit together

Nudge uses a unified Jac backend to keep data synchronized across four components:
```
                  ┌─────────────────────────────────────────┐
                  │          Jac Core Logic & Server        │
                  └────────────────────┬────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
 ┌──────────────┐              ┌──────────────┐              ┌──────────────┐
 │ Web Frontend │              │  Mobile App  │              │ Terminal CLI │
 └──────────────┘              └──────────────┘              └──────────────┘
```

* **Server (`core/`):** Graph engine managing nodes (`Task`, `Folder`, `Subtask`), automated rollover calculations, and Jac `by llm()` prompts.
* **Web (`web/`):** Full-featured dashboard for weekly planning, task classification by filters, and AI task breakdown.
* **Mobile (`mobile/`):** Lightweight view optimized for today's agenda, rapid capture, and quick task completion on the go.
* **CLI (`cli/`):** Fast terminal for keyboard-driven task entry and execution during coding sessions.


Three things that make it impressive:

1. **Per-task priority with live smart ordering** — each task gets assigned with priority, and break-down button to help you plan your day using AI.
2. **Dynamic folders with a folder-filtered calendar & export** — classify
   tasks by folders. Pick a color from a preset rainbow palette to distinguish between tasks in different folders.
   In calendar view, export tasks in your selected folders to sync with other events you have planned on GCal/Macbook Calendar.
3. **Recurring tasks, occurrence by occurrence** — repeat rules (daily,
   weekdays, every week on a day, monthly, annual) add each occurrence as
   its own independent row; completing
   one adds the next occurrence to the list. An optional **repeat until**
   stop date ends the series.
