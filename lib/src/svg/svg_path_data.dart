import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/path.dart';

/// Parses an SVG `<path>` element's `d` attribute into a [PathCommand]
/// list, honoring the path-data mini-language: absolute and relative
/// variants of every command (`M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z`),
/// implicit repetition of the previous command for trailing coordinate
/// groups, and the smooth-curve commands' (`S/s`, `T/t`) control-point
/// reflection.
///
/// Malformed data is truncated rather than thrown on: whatever commands
/// parsed successfully before the first unparseable token are returned —
/// consistent with this package's "never fail the whole render over one
/// bad value" philosophy. Returns an empty list if nothing could be
/// parsed at all (e.g. an empty or entirely malformed `d`).
List<PathCommand> parseSvgPathData(String d) => _PathDataParser(d).parse();

const _commandLetters = 'MmLlHhVvCcSsQqTtAaZz';

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

class _PathDataParser {
  final String _source;
  int _index = 0;

  _PathDataParser(this._source);

  final List<PathCommand> _commands = [];
  Point2D _current = Point2D.zero;
  Point2D _subpathStart = Point2D.zero;

  // The most recent cubic/quadratic control point and which command
  // produced it ('C' or 'Q') — used to reflect the control point for a
  // following S/s or T/t. Reset to null by any command that isn't the
  // matching curve type, per spec ("if there is no previous command or if
  // the previous command was not [...], assume the first control point is
  // coincident with the current point").
  Point2D? _lastControl;
  String? _lastCommandForReflection;

  bool get _atEnd => _index >= _source.length;

  List<PathCommand> parse() {
    while (true) {
      _skipSeparators();
      if (_atEnd) break;
      final commandChar = _source[_index];
      if (!_commandLetters.contains(commandChar)) break;
      _index++;
      if (!_runCommand(commandChar)) break;
    }
    return _commands;
  }

  bool _runCommand(String cmd) {
    switch (cmd) {
      case 'M':
      case 'm':
        if (!_readMoveTo(relative: cmd == 'm')) return false;
        while (_peekNumberAvailable()) {
          if (!_readLineTo(relative: cmd == 'm')) return false;
        }
        return true;
      case 'L':
      case 'l':
        do {
          if (!_readLineTo(relative: cmd == 'l')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'H':
      case 'h':
        do {
          if (!_readAxisLineTo(relative: cmd == 'h', horizontal: true)) {
            return false;
          }
        } while (_peekNumberAvailable());
        return true;
      case 'V':
      case 'v':
        do {
          if (!_readAxisLineTo(relative: cmd == 'v', horizontal: false)) {
            return false;
          }
        } while (_peekNumberAvailable());
        return true;
      case 'C':
      case 'c':
        do {
          if (!_readCubic(relative: cmd == 'c')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'S':
      case 's':
        do {
          if (!_readSmoothCubic(relative: cmd == 's')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'Q':
      case 'q':
        do {
          if (!_readQuadratic(relative: cmd == 'q')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'T':
      case 't':
        do {
          if (!_readSmoothQuadratic(relative: cmd == 't')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'A':
      case 'a':
        do {
          if (!_readArc(relative: cmd == 'a')) return false;
        } while (_peekNumberAvailable());
        return true;
      case 'Z':
      case 'z':
        _commands.add(const ClosePath());
        _current = _subpathStart;
        _lastControl = null;
        _lastCommandForReflection = null;
        return true;
      default:
        return false;
    }
  }

  bool _readMoveTo({required bool relative}) {
    final x = _readNumber();
    final y = _readNumber();
    if (x == null || y == null) return false;
    final point = relative
        ? Point2D(_current.x + x, _current.y + y)
        : Point2D(x, y);
    _commands.add(MoveTo(point));
    _current = point;
    _subpathStart = point;
    _lastControl = null;
    _lastCommandForReflection = null;
    return true;
  }

  bool _readLineTo({required bool relative}) {
    final x = _readNumber();
    final y = _readNumber();
    if (x == null || y == null) return false;
    final point = relative
        ? Point2D(_current.x + x, _current.y + y)
        : Point2D(x, y);
    _commands.add(LineTo(point));
    _current = point;
    _lastControl = null;
    _lastCommandForReflection = null;
    return true;
  }

  bool _readAxisLineTo({required bool relative, required bool horizontal}) {
    final value = _readNumber();
    if (value == null) return false;
    final point = horizontal
        ? Point2D(relative ? _current.x + value : value, _current.y)
        : Point2D(_current.x, relative ? _current.y + value : value);
    _commands.add(LineTo(point));
    _current = point;
    _lastControl = null;
    _lastCommandForReflection = null;
    return true;
  }

  bool _readCubic({required bool relative}) {
    final x1 = _readNumber();
    final y1 = _readNumber();
    final x2 = _readNumber();
    final y2 = _readNumber();
    final x = _readNumber();
    final y = _readNumber();
    if (x1 == null ||
        y1 == null ||
        x2 == null ||
        y2 == null ||
        x == null ||
        y == null) {
      return false;
    }
    final base = _current;
    final c1 = relative ? Point2D(base.x + x1, base.y + y1) : Point2D(x1, y1);
    final c2 = relative ? Point2D(base.x + x2, base.y + y2) : Point2D(x2, y2);
    final end = relative ? Point2D(base.x + x, base.y + y) : Point2D(x, y);
    _commands.add(CubicBezierTo(c1, c2, end));
    _current = end;
    _lastControl = c2;
    _lastCommandForReflection = 'C';
    return true;
  }

  bool _readSmoothCubic({required bool relative}) {
    final x2 = _readNumber();
    final y2 = _readNumber();
    final x = _readNumber();
    final y = _readNumber();
    if (x2 == null || y2 == null || x == null || y == null) return false;
    final base = _current;
    final c2 = relative ? Point2D(base.x + x2, base.y + y2) : Point2D(x2, y2);
    final end = relative ? Point2D(base.x + x, base.y + y) : Point2D(x, y);
    final c1 = _lastCommandForReflection == 'C'
        ? Point2D(2 * base.x - _lastControl!.x, 2 * base.y - _lastControl!.y)
        : base;
    _commands.add(CubicBezierTo(c1, c2, end));
    _current = end;
    _lastControl = c2;
    _lastCommandForReflection = 'C';
    return true;
  }

  bool _readQuadratic({required bool relative}) {
    final x1 = _readNumber();
    final y1 = _readNumber();
    final x = _readNumber();
    final y = _readNumber();
    if (x1 == null || y1 == null || x == null || y == null) return false;
    final base = _current;
    final control = relative
        ? Point2D(base.x + x1, base.y + y1)
        : Point2D(x1, y1);
    final end = relative ? Point2D(base.x + x, base.y + y) : Point2D(x, y);
    _commands.add(QuadraticBezierTo(control, end));
    _current = end;
    _lastControl = control;
    _lastCommandForReflection = 'Q';
    return true;
  }

  bool _readSmoothQuadratic({required bool relative}) {
    final x = _readNumber();
    final y = _readNumber();
    if (x == null || y == null) return false;
    final base = _current;
    final end = relative ? Point2D(base.x + x, base.y + y) : Point2D(x, y);
    final control = _lastCommandForReflection == 'Q'
        ? Point2D(2 * base.x - _lastControl!.x, 2 * base.y - _lastControl!.y)
        : base;
    _commands.add(QuadraticBezierTo(control, end));
    _current = end;
    _lastControl = control;
    _lastCommandForReflection = 'Q';
    return true;
  }

  bool _readArc({required bool relative}) {
    final rx = _readNumber();
    final ry = _readNumber();
    final rotation = _readNumber();
    final largeArc = _readFlag();
    final sweep = _readFlag();
    final x = _readNumber();
    final y = _readNumber();
    if (rx == null ||
        ry == null ||
        rotation == null ||
        largeArc == null ||
        sweep == null ||
        x == null ||
        y == null) {
      return false;
    }
    final base = _current;
    final end = relative ? Point2D(base.x + x, base.y + y) : Point2D(x, y);
    _commands.add(
      ArcTo(
        radiusX: rx,
        radiusY: ry,
        xAxisRotation: rotation * math.pi / 180,
        largeArc: largeArc,
        sweep: sweep,
        point: end,
      ),
    );
    _current = end;
    _lastControl = null;
    _lastCommandForReflection = null;
    return true;
  }

  void _skipSeparators() {
    while (!_atEnd &&
        (_isWhitespace(_source[_index]) || _source[_index] == ',')) {
      _index++;
    }
  }

  bool _peekNumberAvailable() {
    _skipSeparators();
    if (_atEnd) return false;
    final c = _source[_index];
    return _isDigit(c) || c == '.' || c == '+' || c == '-';
  }

  /// A single flag character (`0` or `1`) — arcs' `large-arc-flag` and
  /// `sweep-flag` are always exactly one character, even when packed
  /// against the next number with no separator (e.g. `A5 5 0 0110 20`),
  /// so this deliberately doesn't use the general number tokenizer.
  bool? _readFlag() {
    _skipSeparators();
    if (_atEnd) return null;
    final c = _source[_index];
    if (c == '0') {
      _index++;
      return false;
    }
    if (c == '1') {
      _index++;
      return true;
    }
    return null;
  }

  /// A floating point number, allowing a leading sign, an optional
  /// fractional part, and an optional exponent. Stops at the first `.`
  /// beyond the number's own decimal point, so back-to-back numbers with
  /// no separator (e.g. `0.5.5` meaning `0.5` then `.5`) split correctly.
  double? _readNumber() {
    _skipSeparators();
    final start = _index;
    var i = _index;
    if (i < _source.length && (_source[i] == '+' || _source[i] == '-')) i++;

    var sawDigits = false;
    while (i < _source.length && _isDigit(_source[i])) {
      i++;
      sawDigits = true;
    }

    var sawDot = false;
    if (i < _source.length && _source[i] == '.') {
      sawDot = true;
      i++;
      while (i < _source.length && _isDigit(_source[i])) {
        i++;
        sawDigits = true;
      }
    }

    if (!sawDigits && !sawDot) return null;

    if (i < _source.length && (_source[i] == 'e' || _source[i] == 'E')) {
      var j = i + 1;
      if (j < _source.length && (_source[j] == '+' || _source[j] == '-')) {
        j++;
      }
      if (j < _source.length && _isDigit(_source[j])) {
        i = j;
        while (i < _source.length && _isDigit(_source[i])) {
          i++;
        }
      }
    }

    final value = double.tryParse(_source.substring(start, i));
    if (value == null) return null;
    _index = i;
    return value;
  }
}
