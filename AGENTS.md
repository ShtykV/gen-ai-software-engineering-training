# Course Repository Rules (`gen-ai-software-engineering-training`)

Repository for the **GenAI and Agentic AI for Software Engineering** training course.
Student / Author: **Vasyl Shtyk** (`ShtykV`).

## Structure & Scope
- `homework-1/` through `homework-6/` are **independent** assignments. Keep each homework self-contained inside its own directory and never break or modify other homework folders.
- Always read `homework-X/TASKS.md` first and treat its deliverables and success criteria as the source of truth.

## Git & Pull Request Workflow
- Work on a dedicated branch per assignment: `homework-<N>-submission` (never commit homework implementations directly to `main`).
- Open Pull Requests into **this personal fork's `main` branch** — never into the upstream course repository.
- Assign `Alexey-Popov` as reviewer.
- Write a thorough, standalone PR description (summary of implementation, AI tools/prompts/verification, challenges & fixes, how to run/verify, and 3–5 embedded screenshots). Bare PRs or missing screenshots are rejected.

## Required Deliverables (Every Homework)
- `README.md` — solution overview, approach/architecture, **AI usage documentation**, and **author name (`Vasyl Shtyk`)**.
- `HOWTORUN.md` — reproducible step-by-step environment setup, run, and test instructions.
- `docs/screenshots/` — visual evidence of AI tool usage, running app, and API/test results (also embedded in the PR).
- `demo/` — runnable scripts and sample data/requests whenever specified in `TASKS.md`.

## Quality & Hygiene
- Grading weights: Functionality 30%, AI Usage Documentation 25%, Code Quality 20%, Documentation 15%, Demo & Screenshots 10%.
- Log notable prompts, iterations, and what was manually verified so AI usage documentation stays accurate.
- Never commit secrets, `.env` files, `node_modules/`, `.venv/`, or build/coverage artifacts.
