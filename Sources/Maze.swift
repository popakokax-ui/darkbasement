import Foundation

struct GridPoint: Hashable {
    var x: Int
    var y: Int
}

/// Лабиринт на сетке: true = стена. Размер должен быть нечётным.
final class Maze {
    let size: Int
    private(set) var walls: [[Bool]]

    init(size: Int) {
        self.size = size
        walls = Array(repeating: Array(repeating: true, count: size), count: size)
        carve()
        openLoops()
    }

    private func carve() {
        var stack = [GridPoint(x: 1, y: 1)]
        walls[1][1] = false
        let dirs = [(2, 0), (-2, 0), (0, 2), (0, -2)]
        while let cur = stack.last {
            var options: [(cell: GridPoint, between: GridPoint)] = []
            for d in dirs {
                let nx = cur.x + d.0
                let ny = cur.y + d.1
                if nx > 0, ny > 0, nx < size - 1, ny < size - 1, walls[ny][nx] {
                    options.append((GridPoint(x: nx, y: ny),
                                    GridPoint(x: cur.x + d.0 / 2, y: cur.y + d.1 / 2)))
                }
            }
            if let pick = options.randomElement() {
                walls[pick.between.y][pick.between.x] = false
                walls[pick.cell.y][pick.cell.x] = false
                stack.append(pick.cell)
            } else {
                stack.removeLast()
            }
        }
    }

    /// Пробиваем часть стен, чтобы появились петли (иначе от существа некуда убегать кругами).
    private func openLoops() {
        for _ in 0..<(size * size / 14) {
            let x = Int.random(in: 1..<(size - 1))
            let y = Int.random(in: 1..<(size - 1))
            guard walls[y][x] else { continue }
            let horizontal = !walls[y][x - 1] && !walls[y][x + 1] && walls[y - 1][x] && walls[y + 1][x]
            let vertical = !walls[y - 1][x] && !walls[y + 1][x] && walls[y][x - 1] && walls[y][x + 1]
            if horizontal || vertical { walls[y][x] = false }
        }
    }

    func isWall(_ p: GridPoint) -> Bool {
        if p.x < 0 || p.y < 0 || p.x >= size || p.y >= size { return true }
        return walls[p.y][p.x]
    }

    func freeCells() -> [GridPoint] {
        var result: [GridPoint] = []
        for y in 0..<size {
            for x in 0..<size where !walls[y][x] {
                result.append(GridPoint(x: x, y: y))
            }
        }
        return result
    }

    private let neighbours = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// Расстояния (в клетках) от start до всех достижимых клеток.
    func distances(from start: GridPoint) -> [GridPoint: Int] {
        var dist: [GridPoint: Int] = [start: 0]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let cur = queue[head]
            head += 1
            for d in neighbours {
                let n = GridPoint(x: cur.x + d.0, y: cur.y + d.1)
                if !isWall(n), dist[n] == nil {
                    dist[n] = dist[cur]! + 1
                    queue.append(n)
                }
            }
        }
        return dist
    }

    /// Кратчайший путь: клетки от соседней со start до goal включительно. Пусто, если start == goal или пути нет.
    func path(from start: GridPoint, to goal: GridPoint) -> [GridPoint] {
        if start == goal { return [] }
        var parent: [GridPoint: GridPoint] = [:]
        var visited: Set<GridPoint> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let cur = queue[head]
            head += 1
            if cur == goal { break }
            for d in neighbours {
                let n = GridPoint(x: cur.x + d.0, y: cur.y + d.1)
                if !isWall(n), !visited.contains(n) {
                    visited.insert(n)
                    parent[n] = cur
                    queue.append(n)
                }
            }
        }
        guard parent[goal] != nil else { return [] }
        var result = [goal]
        var cur = goal
        while let p = parent[cur], p != start {
            result.append(p)
            cur = p
        }
        return result.reversed()
    }
}
