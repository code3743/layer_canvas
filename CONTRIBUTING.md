# Contributing to layer_canvas

Thanks for your interest in improving layer_canvas! This document covers how
to get a working dev environment and what we expect from a pull request.

By participating in this project you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Getting started

layer_canvas vendors [Blend2D](https://blend2d.com) as a git submodule and
compiles it from source via a native build hook
(`hook/build.dart`, using `package:native_toolchain_c`), so the submodule
and a C++ toolchain are required even just to run the test suite.

```bash
git clone --recurse-submodules https://github.com/code3743/layer_canvas.git
cd layer_canvas
dart pub get
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### Toolchain requirements

- Dart SDK `^3.12.2` (see `pubspec.yaml`)
- A C++ compiler: `clang` + `cmake` on Linux (the CI image installs these
  explicitly — `gcc` alone is not picked up by
  `package:native_toolchain_c` on Linux), or the standard Xcode /
  MSVC toolchains on macOS / Windows
- [FVM](https://fvm.app) is used to pin the Flutter version for the
  companion `layer_canvas_flutter` package (see `.fvmrc`); not required to
  build this package alone

### Running checks locally

```bash
dart analyze
dart test
dart format --output=none --set-exit-if-changed .
```

All three must pass before a PR is merged; CI runs `dart analyze` and
`dart test` on every push and pull request (see
`.github/workflows/dart.yml`).

## Making changes

- Keep pull requests focused — one logical change per PR.
- Add or update tests under `test/` for any behavioral change.
- Update `CHANGELOG.md` when the change is user-visible (new layer type,
  public API change, bug fix, etc.) — add an entry under the next version
  heading (maintainers will confirm the version number at release time).
- Match the existing code style; `dart format` is authoritative for
  formatting, `analysis_options.yaml` (package:lints/recommended) for lints.
- `layer_canvas` intentionally has no Flutter dependency — don't introduce
  one. Flutter-specific ergonomics belong in
  [`layer_canvas_flutter`](https://github.com/code3743/layer_canvas_flutter)
  instead.

## Commit messages

Use short, imperative commit messages (e.g. `fix: correct gradient stop
clamping`, `feat: add blur filter layer`). This isn't strictly enforced but
keeps `CHANGELOG.md` and release notes easy to write.

## Submitting a pull request

1. Fork the repo and create your branch from `main`.
2. Make your change, following the checks above.
3. Open a PR against `main` using the pull request template — fill in what
   changed and why, and link any related issue.
4. A maintainer will review, request changes if needed, and merge once CI
   is green.

## Reporting bugs / requesting features

Please use the issue templates under "New Issue" — they collect the
information (reproduction steps, platform, Dart/Blend2D version) needed to
act on a report quickly.

## Reporting security issues

Do **not** open a public issue for security vulnerabilities. See
[SECURITY.md](SECURITY.md) for how to report them privately.

## Questions

Open an issue if anything here is unclear.
