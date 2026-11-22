# Agent Mandatory Instructions

Before performing any task, you MUST read and follow `.agents/BEHAVIOR.md`.

These instructions define your mandatory operating behavior, decision-making boundaries, and execution rules.

**All instructions in that file are mandatory. Do not ignore, override, or selectively follow them.**

# Agent Execution Rule: Prioritize Retrieval Over Training

You must operate under a strict retrieval-led execution model. Do not rely on your pre-trained weights for specific codebase structures, API implementations, or modern external data.

* **Codebase First:** Do not assume architectural patterns, file locations, or function signatures exist. You must inspect the local repository state before proposing or writing solutions.
* **External Grounding:** If a task requires external data, library versions, or error resolution, you must actively search for current documentation rather than guessing. 
* **Stop-on-Failure:** If required information cannot be retrieved locally or externally, halt immediately and request clarification. Do not loop or hallucinate alternative fixes.

# Development Guidelines

Feel free to match whatever language I use, but all code, technical terms, and developer jargon must stay in English.
Mixing the two naturally is totally fine—just don't translate technical terms.

Or you can always respond in **English**,
regardless of the language used in the prompt.

## Terminologi
- copas = Copy + Paste
- SSoT = Single Source of Truth
- PoC = Proof of Concept
- selalu menggunakan penulisan penamaan as-is (explicit), hindari konversi terjemahan atau penulisan penamaan (mapping).

## Metodologi
- terapkan polymorphic anti-pattern untuk everything.
- terapkan high coupling dengan facade pattern, sehingga bisa menjadi Hybrid loose coupling.
- terapkan metode sebelum implementasi source code: Observe (Amati), Imitate (Tiru), Modify (Modifikasi).

## Sudo, CLI, Linux System Safety & Command Execution

* **Strictly Prohibited Root Access:** You are strictly prohibited from executing any command using `sudo`, switching users (`su`), or attempting to gain root/elevated privileges automatically.
* **Strictly Prohibited Installations:** You are strictly prohibited from modifying the system state by installing, upgrading, or removing any packages, system tools, or libraries.
* **Mandatory Approval for Risk & Modification:** If a task requires root privileges, package installation, or any destructive modification (such as deleting files, overwriting configurations, or stopping services), you must immediately stop execution. Output the exact command needed and wait for my explicit manual permission.
* **Permitted Safe Actions:** You are allowed to freely execute safe, non-root, read-only, or purely constructive commands (like viewing file contents, checking statuses, or creating new project files) without asking.

### File System Operations

* **Storage Path:** Write all temporary files, scratchpads, caches, runtime scripts, and intermediate outputs exclusively to the pre-existing local directory path `./tmp/`.
* **System Isolation:** Do not use system-level temporary storage paths, environment variables like `$TMPDIR`, or operating system default temp directories.
* **Execution:** When executing any temporary scripts or tools generated during a task, ensure they are run using the correct relative path targeting the ./tmp/ directory.

## Git, Commit & Changes

Do not run any git commit, push, or pull unless explicitly instructed.

When creating or amending commits, always append a `Co-Authored-By: {name} <{email}>` trailer at the very end of the message.

Leave one blank line between the commit body and the trailer.
Replace `{name}` with your full model identity and version.  
If no email is available, omit the entire `<{email}>` part.

When committing, do not hesitate—immediately stage your changed files.
If you detect other changes that did not originate from you, ignore them.
They are from me or another agent working concurrently. Other changes are outside your scope; do not panic or error out.
Focus solely on completing your own commit.
