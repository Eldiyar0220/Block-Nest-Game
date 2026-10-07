import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/blast_game.dart';
import '../game/geometry.dart';
import '../ui/nest_theme.dart';
import 'gem_paint.dart';

const _blocked = Color(0xFFE53935);
const _trayPad = 6.0;
const _trayGap = 8.0;

/// Board, tray and blasts, drawn on Flame's tick instead of rebuilding Flutter.
class NestStage extends FlameGame {
  NestStage({required this.rules});

  BlastGame rules;
  NestColors colors = NestColors.light;
  var dark = false;

  _Playfield? _field;

  @override
  Color backgroundColor() => colors.bg;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    final field = _Playfield(this)..size = size;
    _field = field;
    field.reset();
    await world.add(field);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final field = _field;
    if (field == null) return;
    field.size = size;
    field.layout();
  }

  void bind(BlastGame next) {
    rules = next;
    _field?.reset();
  }

  void stopMotion() {
    _field?.stopMotion();
  }
}

class _Playfield extends PositionComponent with DragCallbacks, TapCallbacks {
  _Playfield(this.stage);

  final NestStage stage;

  final Map<int, Rect> slots = {};
  Rect holdRect = Rect.zero;
  Rect boardRect = Rect.zero;
  double cell = 32;
  double trayCell = 20;
  double trayBottom = 0;

  int? dragSlot;
  Point? grab;
  Offset? finger;

  var blasting = false;
  var blast = 1.0;
  String? praiseWord;
  var praiseLines = 0;
  var praiseCombo = 0;
  var praiseGain = 0;
  var praise = 1.0;
  Offset praiseAt = Offset.zero;
  var arrive = 1.0;
  var epoch = 0;
  var clock = 0.0;
  var _layoutKey = -1;
  int? burstColor;

  final Set<Point> _seen = {};
  final Set<Point> _seenBombs = {};
  final Map<Point, double> pops = {};
  final Map<Point, double> bombPops = {};

  BlastGame get rules => stage.rules;

  void reset() {
    stopMotion();
    epoch = rules.trayEpoch;
    _seen
      ..clear()
      ..addAll(_occupied());
    _seenBombs
      ..clear()
      ..addAll(rules.bombs);
    pops.clear();
    bombPops.clear();
  }

  void stopMotion() {
    blasting = false;
    blast = 1;
    praiseWord = null;
    praise = 1;
    arrive = 1;
    dragSlot = null;
    grab = null;
    finger = null;
    _picking = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    clock += dt;
    _trackPops(dt);
    _syncBlast(dt);
    if (praiseWord != null) {
      praise += dt / 0.32;
      if (praise >= 1) praiseWord = null;
    }
    if (arrive < 1) arrive = math.min(1, arrive + dt / 0.2);
    if (rules.trayEpoch > epoch) {
      epoch = rules.trayEpoch;
      if (rules.level.showsNext) arrive = 0;
    }
    final key = _trayKey();
    if (key != _layoutKey) {
      _layoutKey = key;
      layout();
    }
  }

  int _trayKey() {
    var key = Object.hash(size.x, size.y, rules.level.index);
    for (final piece in rules.tray) {
      key = Object.hash(key, piece?.id ?? -1);
    }
    return key;
  }

  void _syncBlast(double dt) {
    if (rules.bursting.isNotEmpty && !blasting) {
      blasting = true;
      blast = 0;
      praiseLines = rules.lastClear;
      praiseCombo = rules.combo;
      praiseWord = praiseCombo >= 2
          ? 'Combo'
          : BlastGame.praiseFor(praiseLines);
      praiseGain =
          100 * praiseLines * praiseLines +
          BlastGame.bombScore * rules.lastBombs;
      praise = 0;
      praiseAt = _clearAnchor();
      burstColor = rules.placedColor;
    }
    if (!blasting) return;
    blast += dt / 0.16;
    if (blast < 1) return;
    blast = 1;
    blasting = false;
    if (rules.bursting.isNotEmpty) rules.commitBlast();
  }

  void _trackPops(double dt) {
    final occupied = _occupied();
    for (final cell in occupied) {
      if (_seen.add(cell)) pops[cell] = 0;
    }
    _seen.removeWhere((cell) => !occupied.contains(cell));
    final gone = <Point>[];
    pops.forEach((cell, age) {
      final next = age + dt;
      if (next > 0.05) {
        gone.add(cell);
      } else {
        pops[cell] = next;
      }
    });
    for (final cell in gone) {
      pops.remove(cell);
    }

    for (final bomb in rules.bombs) {
      if (_seenBombs.add(bomb)) bombPops[bomb] = 0;
    }
    _seenBombs.removeWhere((bomb) => !rules.bombs.contains(bomb));
    final faded = <Point>[];
    bombPops.forEach((bomb, age) {
      final next = age + dt;
      if (next > 0.07) {
        faded.add(bomb);
      } else {
        bombPops[bomb] = next;
      }
    });
    for (final bomb in faded) {
      bombPops.remove(bomb);
    }
  }

  Set<Point> _occupied() {
    final cells = <Point>{};
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        if (rules.board[r][c] != null) cells.add(Point(r, c));
      }
    }
    return cells;
  }

  void layout() {
    if (size.x < 8 || size.y < 8) return;
    final showsNext = rules.level.showsNext;
    final hasHold = rules.level.hasHold;
    final upcomingH = showsNext ? 52.0 : 0.0;
    final trayH = math.min(120.0, size.y * 0.30);
    final boardRoom = math.max(32.0, size.y - trayH - upcomingH - 12);
    final side = math.min(size.x, boardRoom);
    cell = side / BlastGame.size;
    final boardSize = cell * BlastGame.size;
    boardRect = Rect.fromLTWH(
      (size.x - boardSize) / 2,
      0,
      boardSize,
      boardSize,
    );

    final holdW = hasHold ? 74.0 : 0.0;
    final trayLeft = hasHold ? holdW + _trayGap : 0.0;
    final trayTop = boardRect.bottom + 10;
    holdRect = hasHold
        ? Rect.fromLTWH(2, trayTop - 4, holdW - 8, math.min(94, trayH + 4))
        : Rect.zero;
    _placeTray(trayLeft, trayTop, size.x - trayLeft, trayH - 4);
  }

  void _placeTray(double left, double top, double maxW, double maxH) {
    slots.clear();
    final entries = <(int, BlastPiece)>[];
    for (var i = 0; i < BlastGame.traySlots; i++) {
      final piece = rules.tray[i];
      if (piece != null) entries.add((i, piece));
    }
    if (entries.isEmpty) {
      trayCell = 18;
      trayBottom = top;
      return;
    }
    trayCell = 26;
    while (trayCell > 12 &&
        _trayHeight(entries.map((entry) => entry.$2).toList(), trayCell, maxW) >
            maxH) {
      trayCell -= 1;
    }
    final rows = <List<(int, BlastPiece)>>[];
    var row = <(int, BlastPiece)>[];
    var used = 0.0;
    for (final entry in entries) {
      final w = _slotExtent(entry.$2, trayCell);
      if (row.isNotEmpty && used + _trayGap + w > maxW) {
        rows.add(row);
        row = [];
        used = 0;
      }
      if (row.isNotEmpty) used += _trayGap;
      used += w;
      row.add(entry);
    }
    if (row.isNotEmpty) rows.add(row);

    var y = top;
    for (final line in rows) {
      var width = 0.0;
      var height = 0.0;
      for (final entry in line) {
        final extent = _slotExtent(entry.$2, trayCell);
        width += extent;
        if (extent > height) height = extent;
      }
      width += _trayGap * (line.length - 1);
      var x = left + math.max(0, (maxW - width) / 2);
      for (final entry in line) {
        final extent = _slotExtent(entry.$2, trayCell);
        slots[entry.$1] = Rect.fromLTWH(
          x,
          y + (height - extent) / 2,
          extent,
          extent,
        );
        x += extent + _trayGap;
      }
      y += height + _trayGap;
    }
    trayBottom = y;
  }

  int _spanOf(BlastPiece piece) {
    final width = piece.shapeWidth;
    final height = piece.shapeHeight;
    return width > height ? width : height;
  }

  double _slotExtent(BlastPiece piece, double cell) =>
      _spanOf(piece) * cell + _trayPad * 2;

  Offset _pieceOrigin(Rect rect, BlastPiece piece, double cell) {
    final span = _spanOf(piece);
    return rect.topLeft +
        Offset(
          _trayPad + (span - piece.shapeWidth) * cell / 2,
          _trayPad + (span - piece.shapeHeight) * cell / 2,
        );
  }

  double _trayHeight(List<BlastPiece> pieces, double cell, double maxWidth) {
    var x = 0.0;
    var rowH = 0.0;
    var total = 0.0;
    for (final piece in pieces) {
      final w = _slotExtent(piece, cell);
      final h = w;
      if (x > 0 && x + w > maxWidth) {
        total += rowH + _trayGap;
        x = 0;
        rowH = 0;
      }
      if (x > 0) x += _trayGap;
      x += w;
      if (h > rowH) rowH = h;
    }
    return total + rowH;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (boardRect.isEmpty) return;
    _paintGlow(canvas);
    _paintBoard(canvas);
    _paintLightningFrame(canvas);
    _paintClearFrame(canvas);
    if (rules.level.hasHold) _paintHold(canvas);
    _paintTray(canvas);
    if (rules.level.showsNext) _paintUpcoming(canvas);
    _paintGhost(canvas);
    _paintPraise(canvas);
  }

  void _paintGlow(Canvas canvas) {
    final glow = Rect.fromCenter(
      center: boardRect.center,
      width: boardRect.width * 1.15,
      height: boardRect.height * 1.15,
    );
    canvas.drawOval(
      glow,
      Paint()
        ..color = stage.colors.accent.withValues(
          alpha: stage.dark ? 0.07 : 0.045,
        ),
    );
  }

  void _paintBoard(Canvas canvas) {
    final dragging = rules.draggingSlot == null
        ? null
        : rules.tray[rules.draggingSlot!];
    final preview = rules.clearPreview;
    final aim = dragging == null || preview.isEmpty
        ? null
        : _color(dragging.colorIndex);
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        final rect = _cellRect(r, c);
        final armed = aim != null && preview.contains(Point(r, c));
        if (armed) {
          _paintAimCell(canvas, rect, aim);
          continue;
        }
        final socket = RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.shortestSide * 0.24),
        );
        canvas.drawRRect(socket, Paint()..color = stage.colors.socket);
        canvas.drawRRect(
          socket,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = stage.colors.line,
        );
      }
    }
    if (dragging != null && rules.hoverAnchor != null) {
      for (final part in dragging.cells) {
        final r = rules.hoverAnchor!.r + part.r;
        final c = rules.hoverAnchor!.c + part.c;
        if (r < 0 || c < 0 || r >= BlastGame.size || c >= BlastGame.size) {
          continue;
        }
        final blocked = !rules.hoverValid;
        paintGem(
          canvas,
          _cellRect(r, c),
          blocked ? _blocked : _color(dragging.colorIndex),
          dark: stage.dark,
          pale: blocked ? false : aim == null,
        );
      }
    }

    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        final colorIndex = rules.board[r][c];
        if (colorIndex == null) continue;
        final at = Point(r, c);
        final exploding = rules.bursting.contains(at);
        final aimed = aim != null && preview.contains(at);
        final rect = _cellRect(r, c);
        canvas.save();
        var opacity = 1.0;
        if (exploding) {
          final wipe = _wipe(at);
          opacity = (1 - wipe).clamp(0.0, 1.0);
          if (wipe > 0.92) {
            canvas.restore();
            continue;
          }
          _scaleAbout(canvas, rect.center, _burstScale(wipe));
        } else if (pops.containsKey(at)) {
          final t = Curves.easeOutBack.transform(
            (pops[at]! / 0.05).clamp(0.0, 1.0),
          );
          _scaleAbout(canvas, rect.center, 0.45 + 0.55 * t);
        }
        final gem = aimed ? aim : _color(colorIndex);
        paintGem(
          canvas,
          rect,
          gem.withValues(alpha: opacity),
          dark: stage.dark,
        );
        if ((exploding || aimed) && opacity > 0.12) {
          final flash = exploding
              ? (_burstTint() ?? Colors.white)
              : Colors.white;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(rect.shortestSide * 0.24),
            ),
            Paint()
              ..color = flash.withValues(
                alpha: (exploding ? 0.72 : 0.28) * opacity,
              ),
          );
        }
        canvas.restore();
      }
    }
    if (aim != null) _paintAimLines(canvas, preview, aim);

    for (final bomb in rules.bombs) {
      final exploding = rules.bursting.contains(bomb);
      final rect = _cellRect(bomb.r, bomb.c);
      final pulse = 1 + math.sin(clock * 5 + bomb.r + bomb.c) * 0.035;
      canvas.save();
      var opacity = 1.0;
      if (exploding) {
        final wipe = _wipe(bomb);
        opacity = (1 - wipe).clamp(0.0, 1.0);
        _scaleAbout(canvas, rect.center, _burstScale(wipe) * pulse);
      } else if (bombPops.containsKey(bomb)) {
        final t = Curves.easeOutBack.transform(
          (bombPops[bomb]! / 0.07).clamp(0.0, 1.0),
        );
        opacity = t.clamp(0.0, 1.0);
        _scaleAbout(canvas, rect.center, (0.4 + 0.6 * t) * pulse);
      } else {
        _scaleAbout(canvas, rect.center, pulse);
      }
      final fadeLayer = !exploding && opacity < 1;
      if (fadeLayer) {
        canvas.saveLayer(
          rect.inflate(cell),
          Paint()..color = Colors.white.withValues(alpha: opacity),
        );
      }
      if (!exploding || opacity > 0.04) {
        paintBomb(canvas, rect, glow: exploding ? opacity : 1);
      }
      if (fadeLayer) canvas.restore();
      canvas.restore();
      if (exploding) {
        final t = _wipe(bomb);
        for (var i = 0; i < 3; i++) {
          final angle = i / 3 * math.pi * 2 + bomb.c;
          final travel = rect.width * 0.7 * t;
          final spark =
              rect.center +
              Offset(math.cos(angle) * travel, math.sin(angle) * travel);
          canvas.drawCircle(
            spark,
            rect.width * 0.07 * (1 - t),
            Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 1 - t),
          );
        }
      }
    }
    if (blasting) {
      _paintBeams(canvas);
      _paintShards(canvas);
    }
  }

  void _paintLightningFrame(Canvas canvas) {
    if (!rules.lightningReady) return;
    final pulse = 0.45 + 0.55 * math.sin(clock * 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        boardRect.inflate(3),
        Radius.circular(cell * 0.18),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF7AF0FF).withValues(alpha: 0.28 + 0.5 * pulse),
    );
  }

  double _burstScale(double wipe) {
    if (wipe < 0.28) return 1 + 0.2 * (wipe / 0.28);
    return (1.2 * (1 - (wipe - 0.28) / 0.72)).clamp(0.0, 1.2);
  }

  double _wipe(Point at) {
    final t = Curves.easeInOut.transform(blast.clamp(0.0, 1.0));
    const span = BlastGame.size + 1.2;
    var along = -1.0;
    for (final row in rules.clearRows) {
      if (at.r != row) continue;
      along = math.max(along, t * span - at.c);
    }
    for (final col in rules.clearCols) {
      if (at.c != col) continue;
      along = math.max(along, t * span - at.r);
    }
    if (along < 0) return t;
    return (along / 1.35).clamp(0.0, 1.0);
  }

  void _paintBeams(Canvas canvas) {
    final glow = math.sin(blast.clamp(0.0, 1.0) * math.pi);
    if (glow < 0.02) return;
    final tint = _burstTint() ?? const Color(0xFF7AF0FF);
    for (final row in rules.clearRows) {
      final y = boardRect.top + row * cell;
      _lineGlow(
        canvas,
        Rect.fromLTWH(
          boardRect.left,
          y + cell * 0.12,
          boardRect.width,
          cell * 0.76,
        ),
        glow,
        true,
        tint,
      );
    }
    for (final col in rules.clearCols) {
      final x = boardRect.left + col * cell;
      _lineGlow(
        canvas,
        Rect.fromLTWH(
          x + cell * 0.12,
          boardRect.top,
          cell * 0.76,
          boardRect.height,
        ),
        glow,
        false,
        tint,
      );
    }
  }

  Color? _burstTint() {
    final index = burstColor ?? rules.placedColor;
    if (index == null) return null;
    return _color(index);
  }

  void _paintAimCell(Canvas canvas, Rect rect, Color color) {
    final pulse = 1 + math.sin(clock * 8) * 0.035;
    canvas.save();
    _scaleAbout(canvas, rect.center, pulse);
    paintGem(canvas, rect, color, dark: stage.dark);
    canvas.restore();
  }

  void _paintAimLines(Canvas canvas, Set<Point> preview, Color color) {
    final shine = 0.4 + 0.25 * math.sin(clock * 8);
    for (var r = 0; r < BlastGame.size; r++) {
      if (!_fullLine(preview, row: r)) continue;
      _aimBar(
        canvas,
        Rect.fromLTWH(
          boardRect.left,
          boardRect.top + r * cell + cell * 0.32,
          boardRect.width,
          cell * 0.32,
        ),
        color,
        shine,
      );
    }
    for (var c = 0; c < BlastGame.size; c++) {
      if (!_fullLine(preview, col: c)) continue;
      _aimBar(
        canvas,
        Rect.fromLTWH(
          boardRect.left + c * cell + cell * 0.32,
          boardRect.top,
          cell * 0.32,
          boardRect.height,
        ),
        color,
        shine,
      );
    }
  }

  bool _fullLine(Set<Point> preview, {int? row, int? col}) {
    for (var i = 0; i < BlastGame.size; i++) {
      final at = row != null ? Point(row, i) : Point(i, col!);
      if (!preview.contains(at)) return false;
    }
    return true;
  }

  void _aimBar(Canvas canvas, Rect band, Color color, double shine) {
    final radius = Radius.circular(cell * 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, radius),
      Paint()..color = color.withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: band.center,
          width: band.width * 0.92,
          height: band.height * 0.38,
        ),
        radius,
      ),
      Paint()..color = Colors.white.withValues(alpha: shine),
    );
  }

  void _lineGlow(
    Canvas canvas,
    Rect band,
    double glow,
    bool horizontal,
    Color tint,
  ) {
    final radius = Radius.circular(cell * 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, radius),
      Paint()..color = tint.withValues(alpha: 0.55 * glow),
    );
    final core = horizontal
        ? Rect.fromCenter(
            center: band.center,
            width: band.width,
            height: band.height * 0.28,
          )
        : Rect.fromCenter(
            center: band.center,
            width: band.width * 0.28,
            height: band.height,
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(core, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.88 * glow),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFE14A).withValues(alpha: 0.7 * glow);
    canvas.drawLine(
      horizontal ? band.topLeft : band.topLeft,
      horizontal ? band.topRight : band.bottomLeft,
      edge,
    );
    canvas.drawLine(
      horizontal ? band.bottomLeft : band.topRight,
      horizontal ? band.bottomRight : band.bottomRight,
      edge..color = const Color(0xFF5CFFB0).withValues(alpha: 0.75 * glow),
    );
    for (var i = 0; i < 3; i++) {
      final along = (i + 0.5) / 5;
      final wobble = math.sin(clock * 16 + i) * cell * 0.22;
      final spark = horizontal
          ? Offset(band.left + band.width * along, band.center.dy + wobble)
          : Offset(band.center.dx + wobble, band.top + band.height * along);
      canvas.drawCircle(
        spark,
        cell * 0.055,
        Paint()..color = Colors.white.withValues(alpha: 0.8 * glow),
      );
    }
  }

  void _paintShards(Canvas canvas) {
    for (final at in rules.bursting) {
      final wipe = _wipe(at);
      if (wipe < 0.18) continue;
      final fly = ((wipe - 0.18) / 0.82).clamp(0.0, 1.0);
      final rect = _cellRect(at.r, at.c);
      final colorIndex = rules.board[at.r][at.c];
      final color = colorIndex == null
          ? const Color(0xFFFFD27A)
          : _color(colorIndex);
      for (var i = 0; i < 3; i++) {
        final angle = (i * 2.1) + at.r * 0.4 + at.c * 0.3;
        final dist = cell * (0.2 + 1.05 * fly);
        final spark =
            rect.center +
            Offset(
              math.cos(angle) * dist,
              math.sin(angle) * dist - fly * cell * 0.45,
            );
        canvas.drawCircle(
          spark,
          cell * 0.1 * (1 - fly * 0.75),
          Paint()..color = color.withValues(alpha: 0.9 * (1 - fly)),
        );
      }
    }
  }

  void _paintClearFrame(Canvas canvas) {
    if (praiseWord == null) return;
    final fade = _praiseFade(praise.clamp(0.0, 1.0));
    final edge = _burstTint() ?? const Color(0xFF5CFFF0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        boardRect.deflate(1),
        Radius.circular(cell * 0.16),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = praiseLines >= 2 ? 3 : 2
        ..color = edge.withValues(alpha: 0.85 * fade),
    );
    if (praiseLines < 2 && praiseCombo < 2) return;
    if (praiseCombo >= 3) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          boardRect.inflate(5),
          Radius.circular(cell * 0.2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xFFB44CFF).withValues(alpha: 0.45 * fade),
      );
    }
    const colors = [
      Color(0xFF5CFFF0),
      Color(0xFF7DFF6A),
      Color(0xFFFFE14A),
      Color(0xFFFF7AD9),
    ];
    final loop = 2 * (boardRect.width + boardRect.height);
    const count = 20;
    for (var i = 0; i < count; i++) {
      final at = _ringPoint((i / count) * loop + clock * 28);
      final twinkle = 0.65 + 0.35 * math.sin(clock * 10 + i);
      canvas.drawCircle(
        at,
        cell * 0.07,
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: fade * twinkle),
      );
    }
  }

  Offset _ringPoint(double distance) {
    final width = boardRect.width;
    final height = boardRect.height;
    final loop = 2 * (width + height);
    var left = distance % loop;
    if (left < 0) left += loop;
    if (left < width) return boardRect.topLeft + Offset(left, 0);
    left -= width;
    if (left < height) return boardRect.topRight + Offset(0, left);
    left -= height;
    if (left < width) return boardRect.bottomRight + Offset(-left, 0);
    left -= width;
    return boardRect.bottomLeft + Offset(0, -left);
  }

  Offset _clearAnchor() {
    if (rules.clearRows.isNotEmpty) {
      final row = rules.clearRows[rules.clearRows.length ~/ 2];
      return Offset(boardRect.center.dx, boardRect.top + (row + 0.5) * cell);
    }
    if (rules.clearCols.isNotEmpty) {
      final col = rules.clearCols[rules.clearCols.length ~/ 2];
      return Offset(boardRect.left + (col + 0.5) * cell, boardRect.center.dy);
    }
    return boardRect.center;
  }

  void _paintHold(Canvas canvas) {
    final hot = rules.holdHot;
    final ready = rules.canStore;
    final border = hot
        ? (ready ? stage.colors.accent : stage.colors.danger)
        : stage.colors.line;
    final rrect = RRect.fromRectAndRadius(holdRect, const Radius.circular(16));
    canvas.drawRRect(rrect, Paint()..color = stage.colors.surface);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 1.6 : 1
        ..color = border,
    );
    final piece = rules.held;
    if (piece == null) {
      final icon = Rect.fromCenter(
        center: holdRect.center - const Offset(0, 8),
        width: 18,
        height: 16,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(icon, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = stage.colors.muted.withValues(alpha: ready ? 0.9 : 0.35),
      );
    } else {
      final span = _spanOf(piece);
      final pieceCell = math.min(
        12.0,
        math.min(holdRect.width - 12, holdRect.height - 28) / span,
      );
      _paintPiece(
        canvas,
        piece,
        pieceCell,
        holdRect.center -
            Offset(
              piece.shapeWidth * pieceCell / 2,
              piece.shapeHeight * pieceCell / 2 + 6,
            ),
        rules.isStuck(piece) ? _blocked : _color(piece.colorIndex),
        1,
      );
    }
    final label = rules.level.unlimitedHold
        ? 'запас'
        : (ready ? 'запас 1' : 'запас');
    _label(
      canvas,
      label,
      Offset(holdRect.center.dx, holdRect.bottom - 12),
      stage.colors.muted.withValues(alpha: ready ? 1 : 0.45),
      11,
      weight: FontWeight.w700,
    );
  }

  void _paintTray(Canvas canvas) {
    for (final entry in slots.entries) {
      final piece = rules.tray[entry.key];
      if (piece == null) continue;
      final shown = _arriveOf(entry.key);
      if (shown <= 0) continue;
      final rect = entry.value;
      canvas.save();
      final pop = Curves.easeOutBack.transform(shown);
      final scale = 0.78 + 0.22 * pop;
      final dy = (1 - shown) * 16;
      canvas.translate(rect.center.dx, rect.bottom + dy);
      canvas.scale(scale);
      canvas.translate(-rect.center.dx, -rect.bottom);
      final faded = rules.draggingSlot == entry.key ? 0.28 : shown;
      final body = RRect.fromRectAndRadius(rect, const Radius.circular(16));
      canvas.drawRRect(
        body,
        Paint()..color = stage.colors.surface.withValues(alpha: faded),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = stage.colors.line.withValues(alpha: faded),
      );
      _paintPiece(
        canvas,
        piece,
        trayCell,
        _pieceOrigin(rect, piece, trayCell),
        rules.isStuck(piece) ? _blocked : _color(piece.colorIndex),
        faded,
      );
      _label(
        canvas,
        '↻',
        rect.topRight + const Offset(-8, 8),
        stage.colors.muted.withValues(alpha: faded),
        12,
      );
      if (shown < 1) {
        for (var i = 0; i < 4; i++) {
          final angle = clock * 7 + i * 1.6 + entry.key;
          canvas.drawCircle(
            rect.center +
                Offset(
                  math.cos(angle) * rect.width * 0.4,
                  math.sin(angle) * rect.height * 0.32,
                ),
            2.2,
            Paint()..color = Colors.white.withValues(alpha: (1 - shown) * 0.85),
          );
        }
      }
      canvas.restore();
    }
  }

  void _paintUpcoming(Canvas canvas) {
    final pieces = [for (final piece in rules.upcoming) ?piece];
    if (pieces.isEmpty) return;
    final reveal = arrive >= 1
        ? 1.0
        : const Interval(0.22, 1, curve: Curves.easeOutCubic).transform(arrive);
    final top = math.max(trayBottom, holdRect.bottom) + 4;
    final label = TextPainter(
      text: TextSpan(
        text: 'дальше',
        style: TextStyle(
          color: stage.colors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(0, top));
    var tallest = 1;
    for (final piece in pieces) {
      if (piece.shapeHeight > tallest) tallest = piece.shapeHeight;
    }
    final pieceCell = (34 / tallest).clamp(10.0, 15.0);
    var width = 0.0;
    for (final piece in pieces) {
      width += piece.shapeWidth * pieceCell + 12;
    }
    final origin = Offset((size.x - width) / 2, top + 2);
    if (reveal < 1) {
      final bounds = Rect.fromLTWH(
        origin.dx - 8,
        origin.dy - 4,
        width + 16,
        48,
      );
      canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ImageFilter.blur(
            sigmaX: 2.2 + (1 - reveal) * 6,
            sigmaY: 2.2 + (1 - reveal) * 6,
          )
          ..color = Colors.white.withValues(alpha: 0.8 * reveal),
      );
    }
    var x = origin.dx;
    for (final piece in pieces) {
      _paintPiece(
        canvas,
        piece,
        pieceCell,
        Offset(x, origin.dy),
        _color(piece.colorIndex),
        reveal < 1 ? 1 : 0.4,
      );
      x += piece.shapeWidth * pieceCell + 12;
    }
    if (reveal < 1) canvas.restore();
  }

  void _paintGhost(Canvas canvas) {
    final slot = dragSlot;
    final at = finger;
    final held = grab;
    if (slot == null || at == null || held == null) return;
    final piece = rules.tray[slot];
    if (piece == null) return;
    final blocked = rules.hoverAnchor != null && !rules.hoverValid;
    final lifted = _aim(at);
    _paintPiece(
      canvas,
      piece,
      cell,
      lifted - Offset((held.c + 0.5) * cell, (held.r + 0.5) * cell),
      blocked ? _blocked : _color(piece.colorIndex),
      1,
    );
  }

  void _paintPraise(Canvas canvas) {
    final word = praiseWord;
    if (word == null) return;
    final t = praise.clamp(0.0, 1.0);
    final fade = _praiseFade(t);
    final rise = _praiseRise(t);
    final pop = t < 0.18 ? Curves.easeOutBack.transform(t / 0.18) : 1.0;
    final center = boardRect.center + Offset(0, rise);
    final combo = praiseCombo >= 2;
    final size = combo ? 36.0 : (praiseLines >= 3 ? 46.0 : 40.0);
    final wordAt = combo ? center + const Offset(-36, 0) : center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(0.62 + 0.38 * pop);
    canvas.translate(-center.dx, -center.dy);
    const edge = Color(0xFF3E7BFF);
    for (final delta in const [
      Offset(-1.6, 0),
      Offset(1.6, 0),
      Offset(0, -1.6),
      Offset(0, 1.6),
    ]) {
      _label(
        canvas,
        word,
        wordAt + delta,
        edge.withValues(alpha: fade),
        size,
        weight: FontWeight.w900,
      );
    }
    _label(
      canvas,
      word,
      wordAt,
      Colors.white.withValues(alpha: fade),
      size,
      weight: FontWeight.w900,
    );
    if (combo) {
      final numberAt = center + const Offset(58, 0);
      for (final delta in const [
        Offset(-1.8, 0),
        Offset(1.8, 0),
        Offset(0, -1.8),
        Offset(0, 1.8),
      ]) {
        _label(
          canvas,
          '$praiseCombo',
          numberAt + delta,
          const Color(0xFF2E5FD0).withValues(alpha: fade),
          48,
          weight: FontWeight.w900,
        );
      }
      _label(
        canvas,
        '$praiseCombo',
        numberAt,
        const Color(0xFFFFD84A).withValues(alpha: fade),
        48,
        weight: FontWeight.w900,
      );
    }
    canvas.restore();
    final lift = Curves.easeOutCubic.transform(t) * cell * 1.15;
    _label(
      canvas,
      '+$praiseGain',
      praiseAt - Offset(0, lift),
      const Color(0xFFFFD56A).withValues(alpha: fade),
      22,
      weight: FontWeight.w800,
    );
  }

  void _paintPiece(
    Canvas canvas,
    BlastPiece piece,
    double cell,
    Offset origin,
    Color color,
    double opacity,
  ) {
    final gap = cell * 0.14;
    final block = cell - gap;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final part in piece.cells) {
      paintGem(
        canvas,
        Rect.fromLTWH(
          part.c * cell + gap / 2,
          part.r * cell + gap / 2,
          block,
          block,
        ),
        color.withValues(alpha: opacity),
        dark: stage.dark,
      );
    }
    canvas.restore();
  }

  Rect _cellRect(int r, int c) {
    final gap = cell * 0.14;
    final block = cell - gap;
    return Rect.fromLTWH(
      boardRect.left + c * cell + gap / 2,
      boardRect.top + r * cell + gap / 2,
      block,
      block,
    );
  }

  Color _color(int index) {
    final blocks = stage.colors.blocks;
    return blocks[index % blocks.length];
  }

  double _arriveOf(int order) {
    if (!rules.level.showsNext || arrive >= 1) return 1;
    const step = 0.12;
    final start = order * step;
    final end = 0.58 + order * step;
    final raw = ((arrive - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(raw);
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (rules.busy || rules.gameOver || dragSlot != null) return;
    final point = event.localPosition.toOffset();
    if (rules.lightningReady) {
      final row = _rowAt(point);
      if (row != null) rules.strikeRow(row);
      return;
    }
    if (rules.level.hasHold && _inflated(holdRect).contains(point)) {
      rules.recall();
      return;
    }
    final slot = _slotAt(point);
    if (slot == null || _arriveOf(slot) < 0.35) return;
    rules.rotate(slot);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (rules.busy || rules.gameOver) return;
    final point = event.localPosition.toOffset();
    if (rules.lightningReady) {
      final row = _rowAt(point);
      if (row == null) return;
      _picking = true;
      rules.hoverLightning(row);
      return;
    }
    final slot = _slotAt(point);
    if (slot == null || _arriveOf(slot) < 0.35) return;
    final piece = rules.tray[slot];
    final rect = slots[slot];
    if (piece == null || rect == null) return;
    final local = point - _pieceOrigin(rect, piece, trayCell);
    final col = (local.dx / trayCell).floor();
    final row = (local.dy / trayCell).floor();
    dragSlot = slot;
    grab = nearestCell(piece.cells, row, col);
    finger = point;
    rules.beginDrag(slot);
    _hover(point);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final point = event.localEndPosition.toOffset();
    if (_picking) {
      rules.hoverLightning(_rowAt(point));
      return;
    }
    if (dragSlot == null) return;
    finger = point;
    _hover(point);
  }

  var _drop = true;
  var _picking = false;

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_picking) {
      final row = rules.lightningRow;
      _picking = false;
      if (row != null) {
        rules.strikeRow(row);
      } else {
        rules.hoverLightning(null);
      }
      return;
    }
    final slot = dragSlot;
    dragSlot = null;
    grab = null;
    finger = null;
    if (slot == null) return;
    if (!_drop) {
      _drop = true;
      return;
    }
    if (rules.holdHot) {
      rules.storeDragged();
    } else {
      rules.drop();
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    if (_picking) {
      _picking = false;
      rules.hoverLightning(null);
    }
    _drop = false;
    rules.cancelDrag();
    super.onDragCancel(event);
  }

  Offset _aim(Offset at) => at - Offset(0, cell * 2.05);

  void _hover(Offset point) {
    final aim = _aim(point);
    final local = aim - boardRect.topLeft;
    final onBoard =
        local.dx >= -cell * 0.45 &&
        local.dy >= -cell * 0.45 &&
        local.dx <= boardRect.width + cell * 0.45 &&
        local.dy <= boardRect.height + cell * 0.45;
    final overHold =
        rules.level.hasHold && !onBoard && _inflated(holdRect).contains(aim);
    rules.setHoldHot(overHold);
    final inside = onBoard;
    final col = (local.dx / cell).floor();
    final row = (local.dy / cell).floor();
    final held = grab;
    if (held == null) return;
    rules.hover(Point(row - held.r, col - held.c), active: inside);
  }

  int? _rowAt(Offset point) {
    final local = point - boardRect.topLeft;
    if (local.dx < 0 || local.dy < 0) return null;
    if (local.dx > boardRect.width || local.dy > boardRect.height) return null;
    final row = (local.dy / cell).floor();
    if (row < 0 || row >= BlastGame.size) return null;
    return row;
  }

  int? _slotAt(Offset point) {
    for (final entry in slots.entries) {
      if (entry.value.contains(point)) return entry.key;
    }
    return null;
  }

  Rect _inflated(Rect rect) => rect.inflate(18);

  void _scaleAbout(Canvas canvas, Offset center, double scale) {
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size, {
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}

double _praiseFade(double t) {
  if (t < 0.28) return Curves.easeOut.transform(t / 0.28);
  if (t < 0.62) return 1;
  return Curves.easeIn.transform((1 - (t - 0.62) / 0.38).clamp(0.0, 1.0));
}

double _praiseRise(double t) {
  if (t < 0.28) return 18 * (1 - Curves.easeOutCubic.transform(t / 0.28));
  if (t < 0.62) return 0;
  return -14 *
      Curves.easeInCubic.transform(((t - 0.62) / 0.38).clamp(0.0, 1.0));
}
