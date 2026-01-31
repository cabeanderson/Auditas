# Contributing to Auditas

Thank you for your interest in contributing! We welcome bug reports, feature requests, and code contributions.

## How to Contribute

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally.
3.  **Create a branch** for your feature or fix:
    ```bash
    git checkout -b feature/my-awesome-feature
    ```
4.  **Make your changes**.
5.  **Test your changes**:
    -   Run `make check` to verify dependencies.
    -   Run `auditas check-deps`.
    -   Test the specific tool you modified.
6.  **Commit your changes** with a clear message.
7.  **Push to your branch**:
    ```bash
    git push origin feature/my-awesome-feature
    ```
8.  **Open a Pull Request**.

## Coding Standards

-   **Language**: Bash (compatible with 4.4+).
-   **Style**: 4-space indentation.
-   **Headers**: All source files must include the SPDX license header:
    ```bash
    # Copyright (C) 2026 Your Name
    # SPDX-License-Identifier: GPL-3.0-or-later
    ```
-   **Safety**: Use `set -e` and `set -o pipefail` in scripts.
-   **Output**: Use the logging library (`log_info`, `log_error`) instead of raw `echo`.