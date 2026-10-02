/// A cell on the nest board or inside a piece.
class Point {
  const Point(this.r, this.c);

  final int r;
  final int c;

  @override
  bool operator ==(Object other) =>
      other is Point && other.r == r && other.c == c;

  @override
  int get hashCode => Object.hash(r, c);

  @override
  String toString() => '($r,$c)';
}

/// Slides [cells] so the top-left of their bounding box is the origin.
List<Point> normalize(List<Point> cells) {
  if (cells.isEmpty) return const [];
  var minR = cells.first.r;
  var minC = cells.first.c;
  for (final cell in cells) {
    if (cell.r < minR) minR = cell.r;
    if (cell.c < minC) minC = cell.c;
  }
  final shifted =
      <Point>[for (final cell in cells) Point(cell.r - minR, cell.c - minC)]
        ..sort((a, b) {
          final byRow = a.r.compareTo(b.r);
          return byRow != 0 ? byRow : a.c.compareTo(b.c);
        });
  return shifted;
}

/// Turns a piece a quarter turn to the right and normalizes it.
List<Point> rotateClockwise(List<Point> cells) {
  if (cells.isEmpty) return const [];
  var maxR = cells.first.r;
  for (final cell in cells) {
    if (cell.r > maxR) maxR = cell.r;
  }
  return normalize([for (final cell in cells) Point(cell.c, maxR - cell.r)]);
}

/// Distinct quarter-turns of [cells], starting from the current orientation.
List<List<Point>> rotationsOf(List<Point> cells) {
  final seen = <String>{};
  final result = <List<Point>>[];
  var current = normalize(cells);
  for (var turn = 0; turn < 4; turn++) {
    final key = current.map((cell) => '${cell.r}:${cell.c}').join('|');
    if (seen.add(key)) result.add(current);
    current = rotateClockwise(current);
  }
  return result;
}

bool adjacent(Point a, Point b) {
  final dr = a.r - b.r;
  final dc = a.c - b.c;
  return dr.abs() + dc.abs() == 1;
}

bool isConnected(List<Point> cells) {
  if (cells.length <= 1) return true;
  final remaining = cells.toSet();
  final seen = <Point>{cells.first};
  final queue = <Point>[cells.first];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final next in [
      Point(current.r + 1, current.c),
      Point(current.r - 1, current.c),
      Point(current.r, current.c + 1),
      Point(current.r, current.c - 1),
    ]) {
      if (remaining.contains(next) && seen.add(next)) queue.add(next);
    }
  }
  return seen.length == cells.length;
}

bool sameCells(List<Point> a, List<Point> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Point nearestCell(List<Point> cells, int row, int col) {
  var best = cells.first;
  var bestScore = 1 << 30;
  for (final cell in cells) {
    final score = (cell.r - row).abs() + (cell.c - col).abs();
    if (score < bestScore) {
      bestScore = score;
      best = cell;
    }
  }
  return best;
}
