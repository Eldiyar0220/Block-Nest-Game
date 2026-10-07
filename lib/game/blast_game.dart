import 'dart:math';

import 'package:flutter/foundation.dart';

import 'geometry.dart';
import 'level.dart';
import 'shapes.dart';

enum BlastEvent { pickup, place, reject, rotate, blast, gameOver, undo, hold }

class BlastPiece {
  BlastPiece({required this.id, required this.colorIndex, required this.cells});

  final int id;
  final int colorIndex;
  List<Point> cells;

  int get shapeWidth {
    var maxC = 0;
    for (final cell in cells) {
      if (cell.c > maxC) maxC = cell.c;
    }
    return maxC + 1;
  }

  int get shapeHeight {
    var maxR = 0;
    for (final cell in cells) {
      if (cell.r > maxR) maxR = cell.r;
    }
    return maxR + 1;
  }
}

/// Endless block board: place pieces, and full rows or columns explode away.
/// Medium plants bombs in pairs with a quiet stretch between them. Hard
/// plants one on every move. A cleared line detonates them and takes the
/// surrounding blocks with it.
class BlastGame extends ChangeNotifier {
  BlastGame({Random? random, this.best = 0, this.level = NestLevel.easy})
    : _rng = random ?? Random() {
    board = List.generate(size, (_) => List<int?>.filled(size, null));
    _dealAll();
    _plantOpeningBombs();
  }

  static const size = 8;
  static const traySlots = 3;
  static const undoDepth = 5;
  static const bombScore = 150;

  /// FUN cells placed before the player may pick a row to wipe.
  static const lightningNeed = 8;

  /// One line is Good, two are Excellent, three or more are Perfect.
  static String praiseFor(int lines) {
    if (lines >= 3) return 'Perfect';
    if (lines >= 2) return 'Excellent';
    return 'Good';
  }

  final Random _rng;
  final NestLevel level;

  late final List<List<int?>> board;
  final List<BlastPiece?> tray = List<BlastPiece?>.filled(traySlots, null);
  final List<BlastPiece?> upcoming = List<BlastPiece?>.filled(traySlots, null);

  /// Increments when the blurred queue is promoted into the tray.
  int trayEpoch = 0;
  final Set<Point> bombs = {};
  BlastPiece? held;
  int holdsUsed = 0;
  bool holdHot = false;

  int score = 0;
  int best;
  bool gameOver = false;

  /// FUN charge. Other modes leave it at zero.
  int lightning = 0;

  /// Row under the finger while the player is choosing a lightning strike.
  int? lightningRow;
  String? banner;
  int lastClear = 0;
  int lastBombs = 0;
  int combo = 0;
  final Set<Point> bursting = {};
  final List<int> clearRows = [];
  final List<int> clearCols = [];

  /// Color of the piece that is about to clear, or just cleared, a line.
  int? placedColor;

  int? draggingSlot;
  Point? hoverAnchor;
  bool hoverValid = false;

  void Function(BlastEvent event)? onEvent;
  void Function(int best)? onBest;

  int _nextId = 1;
  int _placements = 0;
  final List<_Turn> _history = [];
  final List<int> _weights = [
    for (final shape in pieceCatalog) pieceWeight(shape.length),
  ];

  bool get busy => bursting.isNotEmpty;

  int get undosLeft => _history.length;

  bool get canUndo => _history.isNotEmpty && draggingSlot == null;

  /// FUN charge is full, so the next tap on the board picks a row to wipe.
  bool get lightningReady =>
      level.isFun && lightning >= lightningNeed && !busy && !gameOver;

  bool get canStore =>
      level.hasHold &&
      !busy &&
      !gameOver &&
      (level.unlimitedHold || holdsUsed < 1);

  List<BlastPiece> get available => [for (final piece in tray) ?piece];

  bool canPlace(BlastPiece piece, Point anchor) {
    return _fits(piece.cells, anchor);
  }

  bool isStuck(BlastPiece piece) => !_anyRotationFits(piece);

  Set<Point> get clearPreview {
    final slot = draggingSlot;
    final anchor = hoverAnchor;
    if (slot == null || anchor == null || !hoverValid) return const {};
    final piece = tray[slot];
    if (piece == null) return const {};
    final lines = _linesIfPlaced(piece.cells, anchor);
    if (lines.isEmpty) return const {};
    return _expandBombs(lines, pending: piece.cells, anchor: anchor);
  }

  void hoverLightning(int? row) {
    final next = lightningReady && row != null && row >= 0 && row < size
        ? row
        : null;
    if (next == lightningRow) return;
    lightningRow = next;
    notifyListeners();
  }

  /// Spends one full charge on the row the player chose.
  void strikeRow(int row) {
    if (!lightningReady || row < 0 || row >= size) return;
    _remember();
    lightning -= lightningNeed;
    lightningRow = null;
    final cells = <Point>{for (var c = 0; c < size; c++) Point(row, c)};
    clearRows
      ..clear()
      ..add(row);
    clearCols.clear();
    lastClear = 1;
    final blast = _expandBombs(cells);
    lastBombs = blast.where(bombs.contains).length;
    bursting
      ..clear()
      ..addAll(blast);
    placedColor = _lineColor(cells) ?? 2;
    _addScore(100 * lastClear * lastClear + bombScore * lastBombs);
    banner = praiseFor(lastClear);
    onEvent?.call(BlastEvent.blast);
    notifyListeners();
  }

  void setHoldHot(bool hot) {
    if (hot == holdHot) return;
    holdHot = hot;
    notifyListeners();
  }

  /// Parks the dragged piece. On medium this spends the single spare.
  void storeDragged() {
    final slot = draggingSlot;
    draggingSlot = null;
    hoverAnchor = null;
    hoverValid = false;
    holdHot = false;
    if (slot == null) return;
    store(slot);
  }

  void store(int slot) {
    if (busy || gameOver || lightningReady) return;
    final piece = tray[slot];
    if (piece == null) return;
    if (!canStore) {
      onEvent?.call(BlastEvent.reject);
      notifyListeners();
      return;
    }
    final swapped = held;
    held = piece;
    tray[slot] = swapped;
    if (!level.unlimitedHold) holdsUsed += 1;
    onEvent?.call(BlastEvent.hold);
    _refillIfEmpty();
    _finishTurn();
  }

  /// Puts the spared piece back into the first empty tray slot.
  void recall() {
    if (busy ||
        gameOver ||
        lightningReady ||
        draggingSlot != null ||
        held == null) {
      return;
    }
    final slot = tray.indexWhere((piece) => piece == null);
    if (slot < 0) {
      onEvent?.call(BlastEvent.reject);
      notifyListeners();
      return;
    }
    tray[slot] = held;
    held = null;
    onEvent?.call(BlastEvent.hold);
    _finishTurn();
  }

  void rotate(int slot) {
    if (busy || gameOver || lightningReady || draggingSlot != null) return;
    final piece = tray[slot];
    if (piece == null) return;
    piece.cells = rotateClockwise(piece.cells);
    onEvent?.call(BlastEvent.rotate);
    notifyListeners();
  }

  void beginDrag(int slot) {
    if (busy || gameOver || lightningReady || draggingSlot != null) return;
    if (tray[slot] == null) return;
    draggingSlot = slot;
    hoverAnchor = null;
    hoverValid = false;
    onEvent?.call(BlastEvent.pickup);
    notifyListeners();
  }

  void hover(Point? anchor, {required bool active}) {
    if (draggingSlot == null) return;
    final next = active ? anchor : null;
    final piece = tray[draggingSlot!];
    final valid = piece != null && next != null && canPlace(piece, next);
    if (next == hoverAnchor && valid == hoverValid) return;
    hoverAnchor = next;
    hoverValid = valid;
    notifyListeners();
  }

  void drop() {
    final slot = draggingSlot;
    if (slot == null) return;
    final piece = tray[slot];
    final anchor = hoverAnchor;
    final wasValid = hoverValid;
    draggingSlot = null;
    hoverAnchor = null;
    hoverValid = false;
    holdHot = false;
    if (piece == null || anchor == null || !wasValid) {
      if (piece != null && anchor != null) onEvent?.call(BlastEvent.reject);
      notifyListeners();
      return;
    }
    _remember();
    for (final cell in piece.cells) {
      board[anchor.r + cell.r][anchor.c + cell.c] = piece.colorIndex;
    }
    tray[slot] = null;
    _addScore(10 * piece.cells.length);
    placedColor = piece.colorIndex;
    if (level.isFun) lightning += piece.cells.length;
    if (_armBlast()) {
      onEvent?.call(BlastEvent.blast);
      notifyListeners();
      return;
    }
    banner = null;
    lastClear = 0;
    lastBombs = 0;
    placedColor = null;
    combo = 0;
    _refillIfEmpty();
    onEvent?.call(BlastEvent.place);
    _continueAfterPlace();
  }

  void cancelDrag() {
    if (draggingSlot == null) return;
    draggingSlot = null;
    hoverAnchor = null;
    hoverValid = false;
    holdHot = false;
    notifyListeners();
  }

  /// Removes the exploded cells after the pop animation.
  void commitBlast() {
    if (bursting.isEmpty) return;
    for (final cell in bursting) {
      board[cell.r][cell.c] = null;
    }
    bombs.removeWhere(bursting.contains);
    _endBurst();
    banner = null;
    lastBombs = 0;
    _refillIfEmpty();
    _finishTurn();
  }

  /// Ends the run when the current tray has nowhere to go.
  void resolve() {
    if (!busy) _finishTurn();
  }

  /// Restores the board to just before the latest placement.
  void undo() {
    if (!canUndo) return;
    _restore(_history.removeLast());
    onEvent?.call(BlastEvent.undo);
    notifyListeners();
  }

  void restart() {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        board[r][c] = null;
      }
    }
    _endBurst();
    banner = null;
    lastClear = 0;
    score = 0;
    combo = 0;
    gameOver = false;
    draggingSlot = null;
    hoverAnchor = null;
    hoverValid = false;
    held = null;
    holdsUsed = 0;
    holdHot = false;
    lightning = 0;
    lightningRow = null;
    bombs.clear();
    lastBombs = 0;
    _placements = 0;
    _history.clear();
    _dealAll();
    _plantOpeningBombs();
    notifyListeners();
  }

  void _remember() {
    _history.add(_capture());
    if (_history.length > undoDepth) _history.removeAt(0);
  }

  _Turn _capture() {
    return _Turn(
      board: [for (final row in board) List<int?>.of(row)],
      tray: _copySlots(tray),
      upcoming: _copySlots(upcoming),
      score: score,
      gameOver: gameOver,
      nextId: _nextId,
      banner: banner,
      lastClear: lastClear,
      combo: combo,
      bombs: Set<Point>.of(bombs),
      placements: _placements,
      held: _copyPiece(held),
      holdsUsed: holdsUsed,
      lightning: lightning,
    );
  }

  void _restore(_Turn turn) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        board[r][c] = turn.board[r][c];
      }
    }
    for (var slot = 0; slot < traySlots; slot++) {
      tray[slot] = turn.tray[slot];
      upcoming[slot] = turn.upcoming[slot];
    }
    score = turn.score;
    gameOver = turn.gameOver;
    _nextId = turn.nextId;
    banner = turn.banner;
    lastClear = turn.lastClear;
    combo = turn.combo;
    lastBombs = 0;
    _placements = turn.placements;
    held = turn.held;
    holdsUsed = turn.holdsUsed;
    lightning = turn.lightning;
    lightningRow = null;
    holdHot = false;
    bombs
      ..clear()
      ..addAll(turn.bombs);
    _endBurst();
    draggingSlot = null;
    hoverAnchor = null;
    hoverValid = false;
  }

  void _dealAll() {
    for (var slot = 0; slot < traySlots; slot++) {
      tray[slot] = _spawn();
    }
    _fillUpcoming();
  }

  void _refillIfEmpty() {
    if (tray.any((piece) => piece != null)) return;
    for (var slot = 0; slot < traySlots; slot++) {
      tray[slot] = upcoming[slot] ?? _spawn();
    }
    _fillUpcoming();
    trayEpoch += 1;
  }

  void _fillUpcoming() {
    for (var slot = 0; slot < traySlots; slot++) {
      upcoming[slot] = _spawn();
    }
  }

  List<BlastPiece?> _copySlots(List<BlastPiece?> slots) {
    return [for (final piece in slots) _copyPiece(piece)];
  }

  BlastPiece? _copyPiece(BlastPiece? piece) {
    if (piece == null) return null;
    return BlastPiece(
      id: piece.id,
      colorIndex: piece.colorIndex,
      cells: List<Point>.of(piece.cells),
    );
  }

  void _plantOpeningBombs() {
    final pace = level.bombPace;
    if (pace == null) return;
    for (var i = 0; i < pace.opening; i++) {
      _plantBomb();
    }
  }

  void _continueAfterPlace() {
    _maybePlantBomb();
    if (_armBlast()) {
      onEvent?.call(BlastEvent.blast);
      notifyListeners();
      return;
    }
    _finishTurn();
  }

  void _maybePlantBomb() {
    final pace = level.bombPace;
    if (pace == null || gameOver) return;
    _placements++;
    if (_placements % pace.every != 0) return;
    for (var i = 0; i < pace.wave; i++) {
      _plantBomb();
    }
  }

  void _plantBomb() {
    final pace = level.bombPace;
    if (pace == null || bombs.length >= pace.cap) return;
    final open = <Point>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (!_hasBlock(r, c)) open.add(Point(r, c));
      }
    }
    if (open.isEmpty) return;
    bombs.add(open[_rng.nextInt(open.length)]);
  }

  bool _armBlast() {
    final lines = _collectLines();
    if (lines.isEmpty) return false;
    combo += 1;
    final blast = _expandBombs(lines);
    lastBombs = blast.where(bombs.contains).length;
    bursting
      ..clear()
      ..addAll(blast);
    placedColor ??= _lineColor(lines);
    final gain = 100 * lastClear * lastClear + bombScore * lastBombs;
    _addScore(gain);
    banner = praiseFor(lastClear);
    return true;
  }

  void _endBurst() {
    bursting.clear();
    clearRows.clear();
    clearCols.clear();
    placedColor = null;
    lightningRow = null;
  }

  int? _lineColor(Set<Point> lines) {
    for (final cell in lines) {
      final color = board[cell.r][cell.c];
      if (color != null) return color;
    }
    return null;
  }

  bool _hasBlock(int r, int c) {
    return board[r][c] != null || bombs.contains(Point(r, c));
  }

  BlastPiece _spawn() {
    final shape = pieceCatalog[_weightedIndex()];
    return BlastPiece(
      id: _nextId++,
      colorIndex: _rng.nextInt(10),
      cells: normalize(shape),
    );
  }

  int _weightedIndex() {
    final total = _weights.fold<int>(0, (sum, weight) => sum + weight);
    var roll = _rng.nextInt(total);
    for (var i = 0; i < _weights.length; i++) {
      roll -= _weights[i];
      if (roll < 0) return i;
    }
    return 0;
  }

  bool _fits(List<Point> cells, Point anchor) {
    if (cells.isEmpty) return false;
    for (final cell in cells) {
      final r = anchor.r + cell.r;
      final c = anchor.c + cell.c;
      if (r < 0 || c < 0 || r >= size || c >= size) return false;
      if (_hasBlock(r, c)) return false;
    }
    return true;
  }

  bool _anyRotationFits(BlastPiece piece) {
    for (final option in rotationsOf(piece.cells)) {
      if (_hasAnchor(option)) return true;
    }
    return false;
  }

  Set<Point> _collectLines() {
    final rows = <int>[];
    final cols = <int>[];
    for (var r = 0; r < size; r++) {
      if (List.generate(size, (c) => _hasBlock(r, c)).every((cell) => cell)) {
        rows.add(r);
      }
    }
    for (var c = 0; c < size; c++) {
      var full = true;
      for (var r = 0; r < size; r++) {
        if (!_hasBlock(r, c)) {
          full = false;
          break;
        }
      }
      if (full) cols.add(c);
    }
    lastClear = rows.length + cols.length;
    clearRows
      ..clear()
      ..addAll(rows);
    clearCols
      ..clear()
      ..addAll(cols);
    final cells = <Point>{};
    for (final r in rows) {
      for (var c = 0; c < size; c++) {
        cells.add(Point(r, c));
      }
    }
    for (final c in cols) {
      for (var r = 0; r < size; r++) {
        cells.add(Point(r, c));
      }
    }
    return cells;
  }

  Set<Point> _linesIfPlaced(List<Point> cells, Point anchor) {
    bool filled(int r, int c) {
      if (_hasBlock(r, c)) return true;
      for (final cell in cells) {
        if (anchor.r + cell.r == r && anchor.c + cell.c == c) return true;
      }
      return false;
    }

    final marked = <Point>{};
    for (var r = 0; r < size; r++) {
      if (List.generate(size, (c) => filled(r, c)).every((cell) => cell)) {
        for (var c = 0; c < size; c++) {
          marked.add(Point(r, c));
        }
      }
    }
    for (var c = 0; c < size; c++) {
      var full = true;
      for (var r = 0; r < size; r++) {
        if (!filled(r, c)) {
          full = false;
          break;
        }
      }
      if (!full) continue;
      for (var r = 0; r < size; r++) {
        marked.add(Point(r, c));
      }
    }
    return marked;
  }

  /// Bombs that sit on a cleared line also wipe the blocks around them.
  /// A bomb caught in that wipe detonates too.
  Set<Point> _expandBombs(
    Set<Point> lines, {
    List<Point> pending = const [],
    Point? anchor,
  }) {
    if (lines.isEmpty) return const {};
    bool occupied(int r, int c) {
      if (_hasBlock(r, c)) return true;
      if (anchor == null) return false;
      for (final cell in pending) {
        if (anchor.r + cell.r == r && anchor.c + cell.c == c) return true;
      }
      return false;
    }

    final blast = <Point>{...lines};
    final queue = <Point>[];
    final seen = <Point>{};
    void consider(Point cell) {
      if (bombs.contains(cell) && seen.add(cell)) queue.add(cell);
    }

    for (final cell in lines) {
      consider(cell);
    }
    var index = 0;
    while (index < queue.length) {
      final bomb = queue[index++];
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final r = bomb.r + dr;
          final c = bomb.c + dc;
          if (r < 0 || c < 0 || r >= size || c >= size) continue;
          final point = Point(r, c);
          if (occupied(r, c)) blast.add(point);
          consider(point);
        }
      }
    }
    return blast;
  }

  bool _hasAnchor(List<Point> cells) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (_fits(cells, Point(r, c))) return true;
      }
    }
    return false;
  }

  /// The offered shape stays as it is when it fits. Otherwise it turns to a
  /// side that fits. A spared piece still counts when an empty slot can take
  /// it back. If nothing can be placed, the run is lost.
  void _finishTurn() {
    if (gameOver) return;
    if (tray.every((piece) => piece == null) && held == null) {
      notifyListeners();
      return;
    }
    var placeable = false;
    for (final piece in tray) {
      if (piece == null) continue;
      if (_align(piece)) placeable = true;
    }
    final spare = held;
    if (spare != null && tray.any((piece) => piece == null) && _align(spare)) {
      placeable = true;
    }
    if (!placeable && !lightningReady) {
      gameOver = true;
      onEvent?.call(BlastEvent.gameOver);
    }
    notifyListeners();
  }

  bool _align(BlastPiece piece) {
    if (_hasAnchor(piece.cells)) return true;
    for (final option in rotationsOf(piece.cells)) {
      if (!_hasAnchor(option)) continue;
      piece.cells = option;
      return true;
    }
    return false;
  }

  void _addScore(int gain) {
    if (gain <= 0) return;
    score += gain;
    if (score > best) {
      best = score;
      onBest?.call(best);
    }
  }
}

class _Turn {
  _Turn({
    required this.board,
    required this.tray,
    required this.upcoming,
    required this.score,
    required this.gameOver,
    required this.nextId,
    required this.banner,
    required this.lastClear,
    required this.combo,
    required this.bombs,
    required this.placements,
    required this.held,
    required this.holdsUsed,
    required this.lightning,
  });

  final List<List<int?>> board;
  final List<BlastPiece?> tray;
  final List<BlastPiece?> upcoming;
  final int score;
  final bool gameOver;
  final int nextId;
  final String? banner;
  final int lastClear;
  final int combo;
  final Set<Point> bombs;
  final int placements;
  final BlastPiece? held;
  final int holdsUsed;
  final int lightning;
}
