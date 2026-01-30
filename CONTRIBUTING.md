# Contributing to dart_dlp

> **Strict Security Protocols in Effect**

Thank you for your interest in `dart_dlp`. This is the world's most performant pure-Dart media engine, and we intend to keep it that way. To maintain the integrity, stability, and security of the codebase, we enforce a strict **Zero-Trust** contribution model.

## 🔒 Security Gatekeeper & CI

We use automated pipelines to vet every line of code before it reaches human review.

### 1. The Security Gatekeeper (`security_check.yml`)
Every Pull Request triggers the Gatekeeper. It performs the following inspections:
-   **Static Analysis**: Runs `dart analyze` to ensure 0% linting errors.
-   **Format Verification**: Runs `dart format --output=none --set-exit-if-changed .` to enforce the Dart style guide.

**If the Gatekeeper fails, your PR is automatically rejected.** Do not waste time asking for a review until the check turns Green.

### 2. The Mass Health Monitor
We maintain a registry of 1,000+ live test URLs (`test/samples.json`).
Before submitting a PR, you **MUST** run the health monitor locally:

```bash
dart run bin/check_health.dart
```

This script spins up a concurrent engine and tests every single supported site. If your change breaks an unrelated extractor (e.g., your Reddit fix broke YouTube), the monitor will scream in **RED**.

**Do not submit broken code.**

---

## 🚫 Restricted Zones

### The Core (`lib/src/core/`)
**Status: LOCKED 🔒**

-   **Owner**: @Hamas
-   **Policy**: No external modifications allowed.

This directory contains the `DlpEngine`, `HamasDownloader`, and `DlpController`. These are finely tuned, high-performance components. Drive-by refactors or "adjustments" to this folder will be closed immediately. If you believe there is a critical bug in the core, open an Issue first.

**Code Owners (`.github/CODEOWNERS`) is configured to enforce this.**

---

## ✅ How to Contribute New Sites

We love new extractors! But you must follow our procedure.

### 1. Use the Factory
Do not manually copy-paste files. Use our generator tool to create a compliant starting point:

```bash
dart run bin/hamas_factory.dart <site_name>
```

This ensures:
-   Correct File Header (`/// Developed by Hamas`)
-   Proper Class Naming
-   Integration with `UserAgentManager`
-   Inheritance from `BaseExtractor`

### 2. Implementation Rules
-   **Parsing**: Prefer `JsonScraper` (Regex/JSON) over HTML DOM parsing where possible. DOM parsing is slow and brittle.
-   **Network**: Always use `headers: {'User-Agent': UserAgentManager.random}` for every request.
-   **Errors**: Throw clear exceptions (e.g., `SiteNotSupportedException`, `AccountPrivateException`).

### 3. Register It
-   Add your new extractor export to `lib/dart_dlp.dart`.
-   Add a test URL to `test/samples.json`.

---

## 📜 Branch & Edit Policy

**Direct pushes to `main` are disabled for everyone.**
**Editing Documentation is Restricted.**

1.  **Fork** the repository.
2.  Create a **Feature Branch** (e.g., `feat/add-vimeo`).
3.  **Commit** your changes.
4.  Open a **Pull Request**.

> **Note**: Do not attempt to modify `README.md`, `CONTRIBUTING.md`, or `.github/CODEOWNERS`. These files are locked to the Owner (@Hamas) only.

Your code belongs to us now.
/// Developed by Hamas | dart_dlp Engine
