# Nudge — Personal Planner in Jac

**Name:** Jiayin (Janae) Shao · **Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner for college students written in Jac.
Change a due date anywhere and it updates everywhere. Its three main features:

1. **List & Calendar views with a downloadable calendar** — see every task
   as a list or a month calendar, with a dynamic **"due within [N]
   [days/weeks]"** window on the Today view, and download your calendar.
2. **AI Task Breakdown** — one click splits an overwhelming task into
   dated, editable 15–45-minute micro-steps. Every new account ships with a
   finished example already broken down under *Grocery shopping*.
3. **Done & Deleted folders with an Auto-Rollover nudge** — Done and Delete folders keep old tasks, each restorable with one click. Unfinished
   past-due tasks nudge to today on load, and a banner reports how many were
   nudged.

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

1. **Per-task priority with live smart ordering** — each task gets assigned with a priority, a
   break-down button, the Calendar dropdown, and **Delete Task**. Lists are ordered due date first and priority second.
2. **Dynamic folders with a folder-filtered calendar & export** — classify
   tasks by course or category. Pick a color from a preset rainbow palette to distinguish between tasks in different folders.
   In the calendar, **Download .ics** exports only for your selected folder's
   tasks. Import other individual tasks to your calendar.
3. **Recurring tasks, occurrence by occurrence** — repeat rules (daily,
   weekdays, every week on a day, monthly, annual) add each occurrence as
   its own independent row; completing
   one adds the next occurrence to the list. An optional **repeat until**
   stop date ends the series — the last matching day on or before it is the
   final occurrence.
