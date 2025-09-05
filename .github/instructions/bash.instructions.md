---
applyTo: '**/*.sh'
---
Provide project context and coding guidelines that AI should follow when generating code, answering questions, or reviewing changes.

# Bash Coding Guidelines
- Use `#!/bin/bash` as the shebang for scripts that require bash-specific features.
- Follow [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html) for naming conventions, indentation, and formatting.
- Use `set -euo pipefail` at the beginning of scripts to ensure robust error handling.
- Use meaningful variable names and avoid using single-letter variable names except in loops.
- Use double quotes around variable expansions to prevent word splitting and globbing.
- Use functions to encapsulate reusable code and improve readability.
- Include comments to explain the purpose of complex code sections.
- Use `getopts` for parsing command-line options.
- Ensure scripts are executable and have appropriate permissions set.
- Reduce "code" clones in bash *.sh scripts by creating reusable functions sourcing common libraries.

# Project Context
This project involves setting up a PXE boot environment for network-based installations and maintenance tasks. The scripts and configurations should facilitate:
- Booting various operating systems and utilities over the network.
- Automating disk imaging and cloning processes.
- Ensuring data integrity and security during disk operations.

# 