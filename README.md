# Nudge — Personal Planner in Jac

**Name:** Jiayin Shao (sjanae@umich.edu)

**Course:** EECS 449, Fall 2026

## Overview

Nudge is an adaptive personal planner for college students written in Jac with components of web frontend, mobile app, and terminal CLI. Change a due date anywhere and it updates everywhere. It has three main features:

1. **List and Calendar views** — See every task as a list or a month calendar, with a dynamic "due within [N]
   [days/weeks]" window on the "Today" view to keep the most urgent tasks on your radar. Download and import tasks into your own calendar.
2. **Recurring tasks, occurrence by occurrence** — Repeat rules (daily, weekdays, every week on a day, monthly, annual) add each occurrence as its own independent task so you can plan ahead.
3. **Done and Deleted folders with an Auto-Rollover nudge** — Done and Delete folders keep old tasks, each restorable with one click. Past-due tasks are moved to today, and a banner reports how many were nudged.

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
jac run cli -- login <username>         # replace <username> with your email
jac run cli -- logout
jac run cli -- today                    # what is due soon
jac run cli -- all                      # assign all open task with a number
jac run cli -- add "EECS 449 HW1" --due 2026-10-05 --folder "EECS 449" --priority high
jac run cli -- add "Team catchup" --due 2026-10-04 --recur weekly --until 2026-12-11

# For the following commands, replace <task> with task number
jac run cli -- breakdown <task>         # breakdown of your tasks using AI
jac run cli -- done <task>
jac run cli -- delete <task>
```

The CLI runs the API colocated in-process, so it hits the same database even when the web server is off.

Run `login` with the same username you use in the browser and `all` will list exactly what the web app shows.

## Mobile App

A lightweight "Today" / "This-week" view for quick task add and completion on the go.

```bash
# stop the web dev server first using control+c on Macbook
jac run _prepare_mobile_web.jac         # prep browser preview
jac run --dev --platform web mobile     # preview in a browser (react-native-web)
jac run --dev mobile                    # native: scan the Expo Go QR (press i / a)
```

> **First native build dies with `Error: Invalid or corrupt jarfile .../gradle-wrapper.jar`?**
> Jac drives Expo with Bun, and Bun appends junk when streaming files out of Expo's
> template archive, so `gradle-wrapper.jar` ends up 13 KB too long and the JVM refuses
> to start it. Run this once after `.jac/mobile-rn` exists, then re-run the command above:
>
> ```bash
> node scripts/patch-expo-tar.mjs
> ```
>
> It patches Expo's extractor in place (idempotent) and re-extracts the template with
> jac's bundled Bun to prove the jar and PNGs come out clean.

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

1. **Per-task priority with live smart ordering** — The priority and AI breakdown assigned to each task help you plan your day using smart AI so you can save the time and energy to actually work on them.
2. **AI Task Breakdown** — Splits an overwhelming large task into 15–45-minute subtasks with one click.
3. **Colorful folders** — Manage your tasks using colorful folders. You get to pick your favorite color for each folder from a rainbow palette.
