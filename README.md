# Nudge — Personal Planner in Jac

* **Name:** Jiayin (Janae) Shao
* **UMID:** 34159055
* **Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner built in Jac that syncs across four
interfaces -- web, mobile, CLI, and the shared server API -- against one
graph database. Designed for college workflows, it keeps tasks manageable
through AI task decomposition, folder filtering, customizable metadata,
automatic rollover, and calendar/email integration.

## Key Features & Value

* **AI Task Decomposition:** Breaks overwhelming assignments into dated
  micro-steps (15–45 min each), each with an **editable time estimate**.
* **Unified dropdowns:** Every changeable setting is one single-line
  dropdown — the dropdown's first line shows the current value, and the
  last entry is `+ add new …`, which opens an inline name input (types,
  folders). No second "edit" icon.
* **Dynamic Folders:** Isolates tasks by course or category, with
  reorder/delete management behind the sidebar gear (pinned to the far
  right of the Views+Folders bar).
* **Done & Deleted folders:** Marking a task done moves it into a `Done`
  folder (shown below "+ new folder", hidden when empty). Deleting a task
  soft-deletes it into a `Deleted` folder that keeps the last 30 days of
  deletions, each restorable with one click.
* **Dual Views (List & Calendar)** with a fill-in-the-blank
  **"due within [N] [days/weeks]"** window for the Today view.
* **One Calendar button per task:** drops down to *Google Calendar* or
  *.ics download* (Apple/Outlook/any calendar).
* **Collaborator email invites:** a task's collaborators (email
  addresses) can be sent an automatic event-invite email — the UI always
  shows a confirmation notice listing the recipients and requires an
  explicit **Send** before anything goes out.
* **Auto-Rollover:** unfinished past-due tasks shift to today on load.
* **Mandatory Due Dates** on task creation.

## Architecture & Component Breakdown

Nudge uses a unified Jac backend (`core/api.jac`, served as a declared
`service` app) to keep data synchronized across four components:

```
                  ┌─────────────────────────────────────────┐
                  │          Jac Core Logic & Server        │
                  │  (Graph DB, AI Engine, Auto-Rollover)   │
                  └────────────────────┬────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
 ┌──────────────┐              ┌──────────────┐              ┌──────────────┐
 │ Web Frontend │              │  Mobile App  │              │ Terminal CLI │
 │ (Full Admin) │              │(Quick Focus) │              │(Rapid Action)│
 └──────────────┘              └──────────────┘              └──────────────┘
```

* **Server (`core/`):** graph nodes (`Task`, `Folder`, `TypeTag`,
  `Subtask`), soft-delete (30-day trash), rollover, calendar export
  (.ics / Google links), invite email (Resend), and `by llm()` prompts.
* **Web (`web/`):** full-featured dashboard: list + calendar views,
  unified dropdowns, Done/Deleted folders, AI breakdown with editable
  estimates, invite confirmation panel.
* **Mobile (`mobile/`):** lightweight Today/This-week view for rapid
  capture and quick completion on the go.
* **CLI (`cli/`):** keyboard-driven terminal client; runs the API
  colocated, so it works offline against the same database.

## Setup & Usage

### Prerequisites
* Python 3.10+
* `jaclang` (`pip install jaclang`, this project pins `==0.37.23`)

No AI API key is needed: the local model (`local:qwen3.5-4b`) is
downloaded automatically on first run.

### 1. Web Application & Server
Run from the root directory:
```bash
git clone https://github.com/sjanae-1/nudge.git
cd nudge
jac run --dev
```
Serves the web UI at `http://localhost:8000` (API on `:8001`).

### 2. CLI Interface
```bash
jac run cli -- today
jac run cli -- add "EECS 449 HW1" --due 2026-10-05 --folder "EECS 449" --people "alex@umich.edu"
jac run cli -- breakdown <task>
jac run cli -- done <task_id>
jac run cli -- all
```

### 3. Mobile View
```bash
jac run mobile --dev
```
Use its own ports (don't run the web and mobile dev servers at the same
time).

### 4. Server API (service app)
`core.api` is declared as a `service` app in `jac.toml`; when the web app
runs it is served under `/api/api/function/<name>` with bearer-token
auth. The web and CLI surfaces both bridge to it.

### Email invites (optional)
Invite sending uses [Resend](https://resend.com). Without a key the
whole invite flow still works up to the confirmation notice, and pressing
Send reports that email isn't configured yet:
```bash
export RESEND_API_KEY="re_..."        # API key from resend.com
# optional overrides:
# export RESEND_FROM="you@yourdomain.com"   (defaults to onboarding@resend.dev)
jac run --dev
```

## Checks

```bash
jac check                 # type-check + lint all apps (web, cli, mobile, api)
jac build web --as client # client bundle
jac build mobile --platform web
```
