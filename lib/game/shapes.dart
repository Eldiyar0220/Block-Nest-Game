import 'geometry.dart';

/// Orientations the tray can deal. The player rotates them on the board.
const List<List<Point>> pieceCatalog = [
  [Point(0, 0)],
  [Point(0, 0), Point(0, 1)],
  [Point(0, 0), Point(0, 1), Point(0, 2)],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(0, 3)],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(0, 3), Point(0, 4)],
  [Point(0, 0), Point(0, 1), Point(1, 0), Point(1, 1)],
  [
    Point(0, 0),
    Point(0, 1),
    Point(0, 2),
    Point(1, 0),
    Point(1, 1),
    Point(1, 2),
  ],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 1)],
  [Point(0, 0), Point(1, 0), Point(2, 0), Point(2, 1)],
  [Point(0, 0), Point(1, 0), Point(2, 0), Point(2, 1), Point(2, 2)],
  [Point(0, 1), Point(1, 0), Point(1, 1), Point(1, 2)],
  [Point(0, 0), Point(0, 1), Point(1, 1), Point(1, 2)],
  [Point(0, 1), Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 1)],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 0)],
  [Point(0, 0), Point(1, 0), Point(2, 0), Point(1, 1)],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 0), Point(2, 0)],
  [
    Point(0, 0),
    Point(0, 1),
    Point(1, 0),
    Point(1, 1),
    Point(2, 0),
    Point(2, 1),
  ],
  [
    Point(0, 0),
    Point(0, 1),
    Point(0, 2),
    Point(1, 0),
    Point(1, 1),
    Point(1, 2),
    Point(2, 0),
    Point(2, 1),
    Point(2, 2),
  ],
];

int pieceWeight(int cellCount) {
  return switch (cellCount) {
    1 => 3,
    2 => 4,
    3 => 5,
    4 => 5,
    5 => 3,
    _ => 1,
  };
}
