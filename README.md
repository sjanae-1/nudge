# Nudge — Personal Planner in Jac

* **Name:** Jiayin (Janae) Shao
* **UMID:** 34159055
* **Course:** EECS 449 — Fall 2026

## Overview

Nudge is an adaptive personal planner built in Jac that syncs across web, mobile, CLI, and server interfaces. Designed specifically for college workflows, it keeps tasks manageable through AI task decomposition, dynamic folder filtering, customizable metadata, and automatic task rollover.

## Key Features & Value

* **AI Task Decomposition:** Breaks overwhelming assignments (e.g., "Finish EECS 449 Project") into actionable micro-steps to eliminate start-up friction.
* **Dynamic Folders:** Isolates tasks by course (`EECS 449`, `MATH 217`) or category (`Misc`) with multi-select filtering across all views.
* **Dual Views (List & Calendar):** Offers both interactive time-blocked calendar grids and configurable list views.
* **Mandatory Due Dates & Auto-Rollover:** Assigns target dates on task creation and automatically shifts unfinished items to today so overdue backlog never piles up.
* **Custom Metadata Columns:** Toggles contextual fields in list view like room location, collaborators, energy level, and priority.

## Architecture & Component Breakdown

Nudge uses a unified Jac backend to keep data synchronized across four components:

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

* **Server (`core/`):** Graph engine managing nodes (`Task`, `Folder`, `Subtask`), automated rollover calculations, and Jac `by llm()` prompts.
* **Web (`web/`):** Full-featured dashboard for weekly planning, column customization, and AI task breakdown.
* **Mobile (`mobile/`):** Lightweight view optimized for today's agenda, rapid capture, and quick task completion on the go.
* **CLI (`cli/`):** Fast terminal client for keyboard-driven task entry and execution during coding sessions.

## Setup & Usage

### Prerequisites
* Python 3.10+
* `jaclang` (`pip install jaclang`)
* `OPENAI_API_KEY` set in your environment:
  ```bash
  export OPENAI_API_KEY="your-api-key"
  ```

### 1. Web Application & Server
Run from the root directory:
```bash
git clone https://github.com/your-username/nudge.git
cd nudge
jac run
```
Starts the server and web UI at `http://localhost:8000`.

### 2. CLI Interface
Execute terminal commands directly:
```bash
jac run cli/main.jac -- today
jac run cli/main.jac -- add "EECS 449 HW1" --due 2026-10-05 --folder EECS449 --room "Duderstadt 2320" --people "Alex"
jac run cli/main.jac -- breakdown "Finish EECS 449 Project"
jac run cli/main.jac -- done <task_id>
```

### 3. Mobile View
Launch the mobile-optimized interface:
```bash
jac run mobile/app.jac
```