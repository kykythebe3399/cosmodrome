# Security Policy

## Overview

Cosmodrome is a local macOS desktop application. It does not expose network services by default.

- **MCP server:** Communicates over stdio only (stdin/stdout). No network listener.
- **Hook server:** Uses Unix domain sockets at `$TMPDIR/cosmodrome-<pid>.sock`. Local access only, scoped to the current user.
- **Control server:** Uses Unix domain sockets at `$TMPDIR/cosmodrome-<uid>.control.sock`. Local access only.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public GitHub issue.
2. Email your report to the maintainers with a description of the vulnerability, steps to reproduce, and potential impact.
3. You will receive an acknowledgment within 72 hours.
4. A fix will be developed and released as soon as possible, with credit to the reporter (unless anonymity is requested).

## Scope

Given that Cosmodrome is a local application, security concerns primarily involve:

- PTY process spawning and privilege handling
- Unix socket permissions and access control
- Input sanitization for commands and configuration files
- Environment variable handling (credentials, tokens)
