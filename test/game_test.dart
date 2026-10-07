import 'dart:math';

import 'package:block_nest/game/blast_game.dart';
import 'package:block_nest/game/geometry.dart';
import 'package:block_nest/game/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full row explodes and disappears', () {
    final game = _game();
    _mono(game);
    for (var c = 0; c < 7; c++) {
      game.board[0][c] = 1;
    }
    game.beginDrag(0);
    game.hover(const Point(0, 7), active: true);
    expect(game.hoverValid, isTrue);
    expect(game.clearPreview.length, 8);
    game.drop();

    expect(game.bursting.length, 8);
    expect(game.board[0][7], isNotNull);
    expect(game.lastClear, 1);
    expect(game.banner, 'Good');
    expect(game.score, 10 + 100);

    game.commitBlast();
    expect(game.bursting, isEmpty);
    expect(game.board[0].every((cell) => cell == null), isTrue);
    expect(game.gameOver, isFalse);
  });

  test('a full column explodes', () {
    final game = _game();
    _mono(game);
    for (var r = 0; r < 7; r++) {
      game.board[r][3] = 2;
    }
    game.beginDrag(0);
    game.hover(const Point(7, 3), active: true);
    game.drop();
    game.commitBlast();

    for (var r = 0; r < BlastGame.size; r++) {
      expect(game.board[r][3], isNull);
    }
  });

  test('a crossing row and column both disappear', () {
    final game = _game();
    _mono(game);
    for (var c = 0; c < 7; c++) {
      game.board[7][c] = 2;
    }
    for (var r = 0; r < 7; r++) {
      game.board[r][7] = 3;
    }
    game.board[0][0] = 4;

    game.beginDrag(0);
    game.hover(const Point(7, 7), active: true);
    game.drop();

    expect(game.lastClear, 2);
    expect(game.banner, 'Excellent');
    expect(game.bursting.length, 15);
    expect(game.score, 10 + 400);
    game.commitBlast();

    expect(game.board[7].every((cell) => cell == null), isTrue);
    for (var r = 0; r < BlastGame.size; r++) {
      expect(game.board[r][7], isNull);
    }
    expect(game.board[0][0], 4);
  });

  test('the tray refills without a piece limit', () {
    final game = _game();
    final first = game.available.map((piece) => piece.id).toSet();
    for (var slot = 0; slot < 3; slot++) {
      _mono(game, slot: slot);
    }
    for (var slot = 0; slot < 3; slot++) {
      game.beginDrag(slot);
      game.hover(Point(1, slot), active: true);
      game.drop();
    }
    expect(game.available, hasLength(3));
    expect(
      game.available.map((piece) => piece.id).toSet().intersection(first),
      isEmpty,
    );
    expect(game.gameOver, isFalse);
    expect(game.board[1][0], isNotNull);
  });

  test('a piece with only a turned gap is offered that way', () {
    final game = _game();
    game.tray[0] = BlastPiece(
      id: 7,
      colorIndex: 2,
      cells: const [Point(0, 0), Point(0, 1)],
    );
    game.tray[1] = null;
    game.tray[2] = null;
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        final verticalGap = c == 0 && (r == 0 || r == 1);
        if (!verticalGap) game.board[r][c] = 1;
      }
    }

    game.resolve();

    expect(game.gameOver, isFalse);
    expect(
      sameCells(game.tray[0]!.cells, const [Point(0, 0), Point(1, 0)]),
      isTrue,
    );
  });

  test('an offered piece with no cell on the board loses the run', () {
    final game = _game();
    game.tray[0] = BlastPiece(
      id: 8,
      colorIndex: 2,
      cells: const [Point(0, 0), Point(0, 1)],
    );
    game.tray[1] = null;
    game.tray[2] = null;
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        if (r != 3 || c != 3) game.board[r][c] = 1;
      }
    }

    game.resolve();

    expect(game.gameOver, isTrue);
    expect(game.board[3][3], isNull);
  });

  test('the run ends only when nothing fits', () {
    final game = _game();
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        game.board[r][c] = 1;
      }
    }
    game.tray[0] = BlastPiece(
      id: 50,
      colorIndex: 0,
      cells: const [Point(0, 0)],
    );
    game.tray[1] = null;
    game.tray[2] = null;
    expect(game.isStuck(game.tray[0]!), isTrue);
    game.resolve();
    expect(game.gameOver, isTrue);
  });

  test('undo puts the last piece back on the tray', () {
    final game = _game();
    _mono(game);
    for (var c = 0; c < 7; c++) {
      game.board[0][c] = 1;
    }
    final pieceId = game.tray[0]!.id;

    game.beginDrag(0);
    game.hover(const Point(0, 7), active: true);
    game.drop();
    game.commitBlast();

    expect(game.score, 110);
    expect(game.best, 110);
    expect(game.undosLeft, 1);

    game.undo();

    expect(game.board[0][7], isNull);
    expect(game.board[0][0], 1);
    expect(game.tray[0]!.id, pieceId);
    expect(game.score, 0);
    expect(game.best, 110);
    expect(game.canUndo, isFalse);
    expect(game.gameOver, isFalse);
  });

  test('only the last five moves can be undone', () {
    final game = _game();
    for (var row = 0; row < 6; row++) {
      _mono(game);
      game.beginDrag(0);
      game.hover(Point(row, 0), active: true);
      game.drop();
    }

    expect(game.undosLeft, BlastGame.undoDepth);
    expect(game.board[0][0], isNotNull);
    expect(game.score, 60);

    for (var step = 0; step < BlastGame.undoDepth; step++) {
      game.undo();
    }

    expect(game.canUndo, isFalse);
    expect(game.board[0][0], isNotNull);
    expect(game.board[1][0], isNull);
    expect(game.board[5][0], isNull);
    expect(game.score, 10);
    expect(game.tray[0], isNotNull);
  });

  test('undo after a loss resumes the run', () {
    final game = _game();
    game.tray[0] = BlastPiece(id: 9, colorIndex: 4, cells: const [Point(0, 0)]);
    game.tray[1] = BlastPiece(
      id: 10,
      colorIndex: 5,
      cells: const [Point(0, 0), Point(0, 1), Point(1, 0), Point(1, 1)],
    );
    game.tray[2] = null;
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        final hole =
            (r == 0 && c == 0) ||
            (r == 0 && c == 1) ||
            (r == 1 && c == 0) ||
            (r >= 2 && c == r);
        if (!hole) game.board[r][c] = 1;
      }
    }

    game.beginDrag(0);
    game.hover(const Point(0, 0), active: true);
    game.drop();

    expect(game.gameOver, isTrue);
    expect(game.canUndo, isTrue);

    game.undo();

    expect(game.gameOver, isFalse);
    expect(game.board[0][0], isNull);
    expect(game.tray[0]!.id, 9);
    expect(game.tray[1]!.id, 10);
  });

  test('restart forgets the undo history', () {
    final game = _game();
    _mono(game);
    game.beginDrag(0);
    game.hover(const Point(2, 2), active: true);
    game.drop();
    expect(game.canUndo, isTrue);

    game.restart();

    expect(game.canUndo, isFalse);
    expect(game.score, 0);
    expect(game.board[2][2], isNull);
  });

  test('a bomb on a cleared line takes the blocks around it', () {
    final game = _game();
    _mono(game);
    for (var c = 0; c < BlastGame.size; c++) {
      if (c == 3 || c == 7) continue;
      game.board[0][c] = 1;
    }
    game.board[1][3] = 2;
    game.board[1][4] = 4;
    game.bombs.add(const Point(0, 3));
    game.bombs.add(const Point(1, 4));

    game.beginDrag(0);
    game.hover(const Point(0, 7), active: true);
    expect(game.clearPreview.contains(const Point(1, 3)), isTrue);
    expect(game.clearPreview.contains(const Point(1, 4)), isTrue);
    game.drop();

    expect(game.lastClear, 1);
    expect(game.lastBombs, 2);
    expect(game.bursting.contains(const Point(1, 3)), isTrue);
    expect(game.bursting.contains(const Point(1, 4)), isTrue);
    expect(game.score, 10 + 100 + BlastGame.bombScore * 2);

    game.commitBlast();
    expect(game.bombs, isEmpty);
    expect(game.board[0].every((cell) => cell == null), isTrue);
    expect(game.board[1][3], isNull);
    expect(game.board[1][4], isNull);
  });

  test('a bomb blocks the cell it sits on', () {
    final game = _game();
    _mono(game);
    game.bombs.add(const Point(2, 2));
    game.beginDrag(0);
    game.hover(const Point(2, 2), active: true);
    expect(game.hoverValid, isFalse);
  });

  test('the blurred next pieces become the tray', () {
    final game = _game();
    expect(game.trayEpoch, 0);
    final next = [for (final piece in game.upcoming) piece!.id];
    for (var slot = 0; slot < 3; slot++) {
      _mono(game, slot: slot);
    }
    for (var slot = 0; slot < 3; slot++) {
      game.beginDrag(slot);
      game.hover(Point(0, slot), active: true);
      game.drop();
    }

    expect(game.tray.map((piece) => piece!.id).toList(), next);
    expect(game.trayEpoch, 1);
    expect(
      game.upcoming
          .map((piece) => piece!.id)
          .toSet()
          .intersection(next.toSet()),
      isEmpty,
    );

    game.undo();
    expect(game.tray[2]!.id, 102);
    expect(game.upcoming.map((piece) => piece!.id).toList(), next);
  });

  test('easy can spare a piece more than once', () {
    final game = _game();
    _mono(game);
    final id = game.tray[0]!.id;
    game.store(0);
    expect(game.held!.id, id);
    expect(game.tray[0], isNull);
    expect(game.holdsUsed, 0);

    game.recall();
    expect(game.held, isNull);
    expect(game.tray[0]!.id, id);

    game.store(0);
    expect(game.held!.id, id);
    expect(game.gameOver, isFalse);
  });

  test('medium can spare a piece only once', () {
    final game = BlastGame(random: Random(1), level: NestLevel.medium);
    game.bombs.clear();
    _mono(game);
    game.tray[1] = BlastPiece(id: 3, colorIndex: 1, cells: const [Point(0, 0)]);
    game.tray[2] = BlastPiece(id: 4, colorIndex: 2, cells: const [Point(0, 0)]);
    final spared = game.tray[0]!.id;
    game.store(0);
    expect(game.holdsUsed, 1);
    expect(game.held!.id, spared);
    expect(game.canStore, isFalse);

    _mono(game);
    final stayed = game.tray[0]!.id;
    game.store(0);
    expect(game.tray[0]!.id, stayed);
    expect(game.held!.id, spared);

    game.tray[1] = null;
    game.recall();
    expect(game.held, isNull);
    expect(game.tray[1]!.id, spared);
    expect(game.canStore, isFalse);
  });

  test('a spared piece in an empty slot prevents a loss', () {
    final game = _game();
    game.tray[0] = BlastPiece(
      id: 1,
      colorIndex: 0,
      cells: const [Point(0, 0), Point(0, 1)],
    );
    game.tray[1] = null;
    game.tray[2] = null;
    game.held = BlastPiece(id: 2, colorIndex: 1, cells: const [Point(0, 0)]);
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        if (r != 4 || c != 4) game.board[r][c] = 1;
      }
    }

    game.resolve();

    expect(game.gameOver, isFalse);
    expect(game.held!.id, 2);
  });

  test('undo restores the spare pocket', () {
    final game = _game();
    _mono(game);
    game.beginDrag(0);
    game.hover(const Point(3, 3), active: true);
    game.drop();
    _mono(game);
    game.store(0);
    expect(game.held, isNotNull);

    game.undo();

    expect(game.held, isNull);
    expect(game.tray[0], isNotNull);
  });

  test('easy stays clear of bombs', () {
    final game = BlastGame(random: Random(1));
    expect(game.level, NestLevel.easy);
    expect(game.bombs, isEmpty);
    for (var row = 0; row < 4; row++) {
      _mono(game);
      game.beginDrag(0);
      game.hover(Point(row, 1), active: true);
      game.drop();
    }
    expect(game.bombs, isEmpty);
  });

  test('medium plants a pair, waits, then plants another pair', () {
    final game = BlastGame(random: Random(1), level: NestLevel.medium);
    final pace = game.level.bombPace!;
    expect(game.bombs, hasLength(pace.opening));
    for (final bomb in game.bombs) {
      expect(game.board[bomb.r][bomb.c], isNull);
    }

    game.bombs.clear();
    for (var row = 0; row < pace.every - 1; row++) {
      _place(game, row);
    }
    expect(game.bombs, isEmpty);

    _place(game, pace.every - 1);
    expect(game.bombs, hasLength(pace.wave));
    for (final bomb in game.bombs) {
      expect(game.board[bomb.r][bomb.c], isNull);
    }

    game.bombs.clear();
    for (var row = 0; row < pace.every - 1; row++) {
      _place(game, row, col: 3);
    }
    expect(game.bombs, isEmpty);
    _place(game, pace.every - 1, col: 3);
    expect(game.bombs, hasLength(pace.wave));

    game.undo();
    expect(game.bombs, isEmpty);
    expect(game.board[pace.every - 1][3], isNull);
  });

  test('hard has no spare pocket', () {
    final game = BlastGame(random: Random(1), level: NestLevel.hard);
    expect(game.level.hasHold, isFalse);
    expect(game.canStore, isFalse);
    final id = game.tray[0]!.id;
    game.store(0);
    expect(game.held, isNull);
    expect(game.tray[0]!.id, id);
  });

  test('hard plants a bomb on every placement', () {
    final game = BlastGame(random: Random(1), level: NestLevel.hard);
    final pace = game.level.bombPace!;
    expect(game.bombs, hasLength(pace.opening));

    game.bombs.clear();
    for (var row = 0; row < pace.cap; row++) {
      _place(game, row);
      expect(game.bombs, hasLength(row + 1));
    }
    _place(game, pace.cap);
    expect(game.bombs, hasLength(pace.cap));
  });

  test('clearing the last gap keeps the run going', () {
    final game = _game();
    _mono(game, slot: 0);
    for (var r = 0; r < BlastGame.size; r++) {
      for (var c = 0; c < BlastGame.size; c++) {
        if (r != 4 || c != 4) game.board[r][c] = 1;
      }
    }
    game.beginDrag(0);
    game.hover(const Point(4, 4), active: true);
    game.drop();
    expect(game.lastClear, 16);
    expect(game.banner, 'Perfect');
    game.commitBlast();
    expect(
      game.board.every((row) => row.every((cell) => cell == null)),
      isTrue,
    );
    expect(game.gameOver, isFalse);
    expect(game.available, isNotEmpty);
  });

  test('fun lightning waits until the player picks a row', () {
    final game = BlastGame(random: Random(1), level: NestLevel.fun);
    expect(game.bombs, isEmpty);
    expect(game.level.hasBombs, isFalse);
    expect(game.lightning, 0);
    expect(game.lightningReady, isFalse);

    _mono(game);
    game.beginDrag(0);
    game.hover(const Point(5, 5), active: true);
    game.drop();
    expect(game.lightning, 1);
    expect(game.bursting, isEmpty);
    expect(game.bombs, isEmpty);

    for (var c = 0; c < 4; c++) {
      game.board[2][c] = 3;
    }
    game.board[1][6] = 5;
    game.lightning = BlastGame.lightningNeed - 1;
    _mono(game);
    game.beginDrag(0);
    game.hover(const Point(4, 4), active: true);
    expect(game.clearPreview, isEmpty);
    game.drop();

    expect(game.lightning, BlastGame.lightningNeed);
    expect(game.lightningReady, isTrue);
    expect(game.bursting, isEmpty);
    expect(game.clearRows, isEmpty);
    expect(game.board[2][0], 3);
    expect(game.board[4][4], isNotNull);

    _mono(game);
    game.beginDrag(0);
    expect(game.draggingSlot, isNull);

    game.hoverLightning(1);
    expect(game.lightningRow, 1);
    game.strikeRow(2);

    expect(game.lightning, 0);
    expect(game.lightningReady, isFalse);
    expect(game.clearRows, [2]);
    expect(game.clearCols, isEmpty);
    expect(game.lastClear, 1);
    expect(game.bursting.contains(const Point(2, 7)), isTrue);
    expect(game.bursting.contains(const Point(1, 6)), isFalse);
    expect(game.board[4][4], isNotNull);

    game.commitBlast();
    expect(game.board[2].every((cell) => cell == null), isTrue);
    expect(game.board[1][6], 5);
    expect(game.board[4][4], isNotNull);

    game.undo();
    expect(game.lightning, BlastGame.lightningNeed);
    expect(game.lightningReady, isTrue);
    expect(game.board[2][0], 3);

    game.restart();
    expect(game.lightning, 0);
    expect(game.board[4][4], isNull);
  });

  test('a fun line clear stays a single line until lightning is full', () {
    final game = BlastGame(random: Random(1), level: NestLevel.fun);
    _mono(game);
    for (var c = 0; c < 7; c++) {
      game.board[0][c] = 1;
    }
    for (var c = 0; c < 3; c++) {
      game.board[3][c] = 4;
    }
    game.lightning = 2;
    game.beginDrag(0);
    game.hover(const Point(0, 7), active: true);
    game.drop();

    expect(game.combo, 1);
    expect(game.lastClear, 1);
    expect(game.clearRows, [0]);
    expect(game.clearCols, isEmpty);
    expect(game.lightning, 3);
    expect(game.board[3][0], 4);
  });
}

BlastGame _game() => BlastGame(random: Random(1), best: 0);

void _place(BlastGame game, int row, {int col = 1}) {
  _mono(game);
  while (game.bombs.contains(Point(row, col)) || game.board[row][col] != null) {
    col++;
  }
  game.beginDrag(0);
  game.hover(Point(row, col), active: true);
  game.drop();
}

void _mono(BlastGame game, {int slot = 0}) {
  game.tray[slot] = BlastPiece(
    id: 100 + slot,
    colorIndex: 1,
    cells: const [Point(0, 0)],
  );
}
