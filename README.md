# Nudge — Personal Planner in Jac

**Name:** Jiayin (Janae) Shao

**Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner for college students written in Jac with components of web frontend, mobile app, and terminal CLI. Change a due date anywhere and it updates everywhere. It has three main features:

1. **List and Calendar views** — See every task
   as a list or a month calendar, with a dynamic **"due within [N]
   [days/weeks]"** window on the "Today" view to keep the most urgent tasks on your radar. Download and import your tasks into your own calendar.
2. **AI Task Breakdown** — Splits an overwhelming task into
   dated, editable 15–45-minute subtasks with one click.
3. **Done and Deleted folders with an Auto-Rollover nudge** — "Done" and "Delete" folders keep old tasks, each restorable with one click. Unfinished
   past-due tasks are moved to today, and a banner reports how many were
   nudged.

## Setup & Run

**Prerequisites:** Python 3.10+ and `pip install jaclang==0.37.23`.

```bash
git clone https://github.com/sjanae-1/nudge.git
cd nudge
jac install            # Python deps: litellm + llama-cpp-python for the local AI model
jac run --dev          # web app + API → http://localhost:8000 (API on :8001)
```

Click on **Create account** on the login page to register for a new account.

## CLI

```bash
jac run cli -- login <username>         # sign in: CLI then shows YOUR web tasks
jac run cli -- logout                   # back to the shared anonymous list
jac run cli -- today                    # what is due soon
jac run cli -- all                      # assign every open task with a number
jac run cli -- add "EECS 449 HW1" --due 2026-10-05 --folder "EECS 449" --priority high
jac run cli -- add "Team catchup" --due 2026-10-04 --recur weekly --until 2026-12-11
# For the following commands, replace <task> with task number
jac run cli -- breakdown <task>         # AI micro-steps
jac run cli -- done <task>              # task number or title fragment
jac run cli -- delete <task>            # move a task to the Delete folder
```

The CLI runs the API colocated in-process, so it hits the same database even
when the web server is off. Run `login`
with the same username you use in the browser and `all` will list exactly
what the web app shows.

## Mobile App

A lightweight "Today" / "This-week" view for quick task add and completion on the go.

```bash
# stop the web dev server first — both claim the 800x ports
jac run _prepare_mobile_web.jac         # one-shot: compile the mobile client for the browser preview
jac run --dev --platform web mobile     # preview in a browser (react-native-web)
jac run --dev mobile                    # native: scan the Expo Go QR (press i / a)
```

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


## Three things that make Nudge impressive:

1. **Per-task priority with live smart ordering** — The priority and AI breakdown assigned to each task help you plan your day using smart AI so you can save the time and energy to actually work on these tasks.
2. **Dynamic folders with a folder-filtered calendar & export** — Classify
   tasks by colorful folders you get to pick from a rainbow palette. In calendar view, export tasks in your selected folders to be in sync with other events you have planned on GCal/Macbook Calendar.
3. **Recurring tasks, occurrence by occurrence** — Repeat rules (daily,
   weekdays, every week on a day, monthly, annual) add each occurrence as
   its own independent task so you can plan ahead.
