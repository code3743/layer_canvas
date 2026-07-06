# Security Policy

## Supported Versions

layer_canvas is currently in beta (`0.x`). Security fixes are made against
the latest published version on [pub.dev](https://pub.dev/packages/layer_canvas)
and the `main` branch. There is no long-term support for older `0.x`
releases — please upgrade to the latest version before reporting an issue.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub
issues, discussions, or pull requests.**

Instead, report them privately using one of these channels:

- [GitHub Security Advisories](https://github.com/code3743/layer_canvas/security/advisories/new)
  for this repository (preferred), or
- Email jotalopez.dev@gmail.com

Please include:

- A description of the vulnerability and its potential impact
- Steps to reproduce (a minimal `Scene`/`Layer` snippet if applicable)
- The affected version(s) and platform (Android/iOS/macOS/Linux/Windows)

## Scope

layer_canvas renders untrusted input in two places that matter most from a
security standpoint:

- **Blend2D (native, via FFI)** — vendored as a git submodule and compiled
  into this package. Memory-safety issues in decoding images, fonts, or SVGs
  through this path are in scope.
- **SVG / font parsing** (`lib/src/svg`, font registry) — malformed input
  causing crashes, panics, or memory corruption is in scope.

Denial-of-service via pathologically large inputs (e.g. an enormous canvas
size) is a known, low-severity class — please still report it, but expect
it to be triaged as lower priority than memory-safety issues.

## Response

We aim to acknowledge reports within 5 business days and to release a fix
or mitigation, or provide a timeline, within 30 days depending on severity
and complexity.
