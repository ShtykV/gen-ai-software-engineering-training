# 🎧 Homework 2: Intelligent Customer Support System

## 📋 Overview

Build a customer support ticket management system that imports tickets from multiple file formats, automatically categorizes issues, and assigns priorities. Implement a web front-end for agents to manage tickets day to day. Focus on applying the **Context-Model-Prompt** while generating comprehensive tests and documentation using AI tools. Also install a **memory plugin**, use it across sessions, and commit the memory-related changes with your submission.

---

## 🎯 Learning Objectives

- ✅ Master the **Context-Model-Prompt framework** in practice
- ✅ Generate comprehensive test suites with AI (>85% coverage)
- ✅ Create multi-level documentation
- ✅ Build a functional front-end that consumes the ticket API
- ✅ Install and use an AI **memory plugin** so project context persists across sessions

---

## 🛠️ Requirements

**Tools:** Use AI coding tools

**Backend Tech Stack:** Choose one - Node.js/Express, Python/Flask/FastAPI, or Java/Spring Boot

**Front-End Tech Stack:** Your choice (e.g., React, Vue, Svelte, plain HTML/CSS/JS)

---

## 📝 Tasks

### Task 1: Multi-Format Ticket Import API

Create a REST API for support tickets with these endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/tickets` | Create a new support ticket |
| `POST` | `/tickets/import` | Bulk import from CSV/JSON/XML |
| `GET` | `/tickets` | List all tickets (with filtering) |
| `GET` | `/tickets/:id` | Get specific ticket |
| `PUT` | `/tickets/:id` | Update ticket |
| `DELETE` | `/tickets/:id` | Delete ticket |

**Ticket Model:**
```json
{
  "id": "UUID",
  "customer_id": "string",
  "customer_email": "email",
  "customer_name": "string",
  "subject": "string (1-200 chars)",
  "description": "string (10-2000 chars)",
  "category": "account_access | technical_issue | billing_question | feature_request | bug_report | other",
  "priority": "urgent | high | medium | low",
  "status": "new | in_progress | waiting_customer | resolved | closed",
  "created_at": "datetime",
  "updated_at": "datetime",
  "resolved_at": "datetime (nullable)",
  "assigned_to": "string (nullable)",
  "tags": ["array"],
  "metadata": {
    "source": "web_form | email | api | chat | phone",
    "browser": "string",
    "device_type": "desktop | mobile | tablet"
  }
}
```

**Requirements:**
- Parse CSV, JSON, and XML file formats
- Validate all required fields (email format, string lengths, enums)
- Return bulk import summary: total records, successful, failed with error details
- Handle malformed files gracefully with meaningful error messages
- Use appropriate HTTP status codes (201, 400, 404, etc.)

---

### Task 2: Auto-Classification

Implement automatic ticket categorization and priority assignment.

**Categories:**
- `account_access` - login, password, 2FA issues
- `technical_issue` - bugs, errors, crashes
- `billing_question` - payments, invoices, refunds
- `feature_request` - enhancements, suggestions
- `bug_report` - defects with reproduction steps
- `other` - uncategorizable

**Priority Rules:**
- **Urgent**: "can't access", "critical", "production down", "security"
- **High**: "important", "blocking", "asap"
- **Medium**: default
- **Low**: "minor", "cosmetic", "suggestion"

**Endpoint:**
```
POST /tickets/:id/auto-classify
```

**Response includes:** category, priority, confidence score (0-1), reasoning, keywords found

**Requirements:**
- Auto-run on ticket creation (optional flag)
- Store classification confidence
- Allow manual override
- Log all decisions

---

### Task 3: AI-Generated Test Suite

Generate comprehensive tests achieving **>85% code coverage**.

**Required Test Files:**

```
tests/
├── test_ticket_api          # API endpoints (11 tests)
├── test_ticket_model        # Data validation (9 tests)
├── test_import_csv          # CSV parsing (6 tests)
├── test_import_json         # JSON parsing (5 tests)
├── test_import_xml          # XML parsing (5 tests)
├── test_categorization      # Classification (10 tests)
├── test_integration         # End-to-end workflows (5 tests)
├── test_performance         # Benchmarks (5 tests)
└── fixtures/                   # Sample data files
```

**Test Coverage Requirements:**
- Overall: >85%

---

### Task 4: Multi-Level Documentation

Generate 5 documentation files for different audiences:

**1. README.md** (Developers)
- Project overview and features
- Architecture diagram (Mermaid)
- Installation and setup instructions
- How to run tests
- Project structure

**2. API_REFERENCE.md** (API Consumers)
- All endpoints with request/response examples
- Data models and schemas
- Error response formats
- cURL examples for each endpoint

**3. ARCHITECTURE.md** (Technical Leads)
- High-level architecture diagram (Mermaid)
- Component descriptions
- Data flow diagrams (Mermaid sequence diagrams)
- Design decisions and trade-offs
- Security and performance considerations

**4. TESTING_GUIDE.md** (QA Engineers)
- Test pyramid diagram (Mermaid)
- How to run tests
- Sample test data locations
- Manual testing checklist
- Performance benchmarks table

**Requirements:**
- Use different AI models for different doc types
- Include at least 3 Mermaid diagrams across documents

---

### Task 5: Front-End Application

Build a web UI for the customer support ticket management system.

**Tech stack:** Your choice — pick any framework or library you prefer (React, Vue, Angular, Svelte, etc.) or use plain HTML/CSS/JavaScript.

**Required UI features:**
- List tickets with filtering by category, priority, and status
- Create and edit tickets via forms with client-side validation
- View ticket details (including classification results and metadata)
- Bulk import tickets from CSV/JSON/XML files
- Trigger auto-classification for a ticket and display the result (category, priority, confidence, reasoning)
- Clear error and success feedback for API operations

**Requirements:**
- Connect to the REST API from Tasks 1–2 (no hardcoded ticket data in the UI)
- Responsive layout that works on desktop and mobile
- Include setup/run instructions in the project README

---

### Task 6: Integration & Performance Tests

Implement end-to-end tests.

**Integration Tests:**
- Complete ticket lifecycle workflow
- Bulk import with auto-classification verification
- Concurrent operations (20+ simultaneous requests)
- Combined filtering by category and priority

---

### Task 7: Memory Plugin — Install, Use, and Commit

Set up a persistent **memory plugin** for your AI coding tool so useful project context survives across chat sessions. Use it while building Homework 2, then commit the memory-related changes to your submission branch.

**Recommended options** (pick one that matches your toolchain):

| Tool | Memory plugin / feature | Install hint |
|------|-------------------------|--------------|
| Claude Code | [claude-mem](https://github.com/thedotmack/claude-mem) | `/plugin marketplace add thedotmack/claude-mem && /plugin install claude-mem` or `npx claude-mem install` |
| Cursor | Cursor Memories / Agent Memories (or an equivalent memory MCP/plugin) | Save durable project facts via the product memory UI / MCP |
| Other AI IDEs | Any persistent memory / RAG / notes plugin for your agent | Document which one you chose and how you installed it |

**What to store in memory (examples):**
- Your chosen backend and front-end stack for this homework
- Ticket model constraints, category/priority rules, and API endpoint map
- Decisions you made (validation approach, classification heuristics, test layout)
- Recurring pitfalls and how you fixed them (import edge cases, CORS, etc.)
- How to run the app and tests locally

**Requirements:**
1. **Install** the memory plugin (or enable the built-in memory feature) and confirm it is active in your AI tool.
2. **Work with memory** during implementation — add or update at least **5** durable memory entries related to this homework (not one-off chat fluff).
3. **Use memory in a later session** — start a new chat/session and rely on stored memory (or memory search) to continue work without re-pasting the full project context. Capture evidence (screenshot or short transcript excerpt).
4. **Commit memory changes** to your homework branch:
   - Commit any project-local memory artifacts your plugin creates (e.g. memory DB/export, `MEMORY.md`, `.claude-mem/`, MCP config snippets) **if they are meant to be shared with the repo**.
   - Do **not** commit secrets, API keys, private personal data, or machine-local absolute paths. Use `<private>` / ignore rules where the plugin supports them.
   - If memory lives only in a cloud/product account (no files to commit), still commit a `docs/memory-setup.md` that records: plugin name, install steps, what you stored, and how a teammate would reproduce it — plus a screenshot of the memory entries or search UI.
5. Document the workflow briefly in your project `README.md` under a **Memory plugin** section.

**Evidence to include:**
- Screenshot of the installed/active memory plugin (or memory settings)
- Screenshot or export showing ≥5 homework-related memory entries
- Screenshot of a follow-up session where the agent recalls or retrieves that memory
- Git commit(s) on your submission branch that include the memory artifacts and/or `docs/memory-setup.md`

---

## 📦 Deliverables

### 1️⃣ Source Code

### 2️⃣ Test Coverage Report
- Coverage report showing >85%
- Screenshot in `docs/screenshots/test_coverage.png`

### 3️⃣ UI Screenshot
- Screenshot of the running front-end in `docs/screenshots/ui.png`
- Show the main ticket list or another representative screen with real data

### 4️⃣ Sample Data
- `sample_tickets.csv` (50 tickets)
- `sample_tickets.json` (20 tickets)
- `sample_tickets.xml` (30 tickets)
- Invalid data files for negative tests

### 5️⃣ Memory Plugin Evidence
- Memory setup notes in `README.md` (and `docs/memory-setup.md` if memory is cloud-only)
- Screenshots in `docs/screenshots/` (plugin active, memory entries, recall in a new session)
- Commit(s) on your branch that add/update memory artifacts or the memory setup doc

---

<div align="center">

**Good luck! 🍀**

</div>
