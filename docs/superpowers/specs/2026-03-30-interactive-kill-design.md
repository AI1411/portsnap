# Interactive Kill Selection — Design Spec

**Date:** 2026-03-30
**Status:** Approved

---

## 概要

`pps` コマンドのデフォルト動作をインタラクティブ選択モードに変更する。
ユーザーは矢印キーでポートエントリを選択し、Enter で確認プロンプトを経て対象プロセスに SIGTERM を送信できる。

---

## アーキテクチャ

### ファイル構成

```
src/output/select.zig   ← 新規作成（インタラクティブ選択TUI）
src/main.zig            ← .list ブランチのデフォルト動作を select.run() に変更
build.zig               ← select モジュールを追加
```

### 全体フロー

```
pps 起動
  ↓
ポートをスキャン（一度だけ）
  ↓
--json / -p フラグ指定あり？
  ├─ Yes → 従来の非インタラクティブ出力（変更なし）
  └─ No  → インタラクティブモード起動
              ↓
           ターミナルをrawモードに切り替え
              ↓
           一覧を描画（選択行をハイライト）
              ↓
           キー入力ループ
              ├─ ↑/↓ or k/j  : カーソル移動 → 再描画
              ├─ Enter        : 確認プロンプト表示
              │     ├─ y      : SIGTERM 送信 → 終了
              │     └─ n/Esc  : プロンプト解除 → ループ継続
              └─ q/Esc        : rawモード解除 → 終了
```

---

## コンポーネント詳細

### `src/output/select.zig`

**公開API:**

```zig
/// インタラクティブ選択モードを起動する。
/// ユーザーが選択してkillするか、qで終了するまでブロックする。
pub fn run(allocator: std.mem.Allocator, entries: []const types.PortEntry) !void
```

**rawモード管理:**

```zig
// 既存設定を保存し、終了時に必ず復元（errdefer 含む）
var orig: std.posix.termios = try std.posix.tcgetattr(stdin_fd);
defer std.posix.tcsetattr(stdin_fd, .FLUSH, orig) catch {};

// rawモードに変更（canonical off, echo off）
var raw = orig;
raw.lflag.ICANON = false;
raw.lflag.ECHO = false;
raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
```

**内部状態:**

```zig
cursor: usize,       // 現在の選択行インデックス
in_prompt: bool,     // 確認プロンプト表示中か
entries: []const types.PortEntry,
```

---

## キー入力仕様

| キー | バイト列 | 動作 |
|------|----------|------|
| `↑` | `\x1b[A` | カーソルを1行上に移動 |
| `↓` | `\x1b[B` | カーソルを1行下に移動 |
| `k` | `0x6B` | カーソルを1行上に移動 |
| `j` | `0x6A` | カーソルを1行下に移動 |
| `Enter` | `0x0D` | 確認プロンプト表示（PIDがある場合のみ） |
| `y` (プロンプト中) | `0x79` | SIGTERM 送信 → 終了 |
| `n` (プロンプト中) | `0x6E` | プロンプト解除 |
| `Esc` | `0x1B` | プロンプト中なら解除、通常時は終了 |
| `q` | `0x71` | 終了 |

---

## 画面レイアウト

```
pps — 34 ports  [↑↓/jk] 移動  [Enter] kill  [q] 終了

 PROTO  LOCAL              STATE         PID     PROCESS
────────────────────────────────────────────────────────
 tcp    0.0.0.0:8080       LISTEN        1234    nginx
▶tcp    0.0.0.0:3000       LISTEN        5678    node        ← 選択行（反転表示）
 tcp    0.0.0.0:5432       LISTEN        9012    postgres
 tcp    0.0.0.0:6379       LISTEN        -       redis-ser   ← PIDなし（killできない）

Kill process node (PID 5678)? [y/N]               ← プロンプト（最下部）
```

- 選択行は ANSI 反転表示 (`\x1b[7m` ... `\x1b[0m`)
- PID が null のエントリはカーソル移動可能だが Enter でプロンプトは出ない
- 画面描画の前に `\x1b[2J\x1b[H`（画面クリア + カーソル先頭）

---

## kill 実行

```zig
try signal.sendSignal(entry.pid.?, .SIGTERM);
```

既存の `src/utils/signal.zig` の `sendSignal` をそのまま流用する。

---

## エラーハンドリング

| ケース | 対応 |
|--------|------|
| TTY でない（パイプ） | インタラクティブモードをスキップ、従来出力 |
| kill 権限なし | エラーメッセージを最下部に表示してループ継続 |
| エントリ0件 | 「ポートが見つかりません」を表示して終了 |
| rawモード復元失敗 | 無視（すでに終了フロー中のため） |

---

## 非インタラクティブモードの維持

以下のケースでは従来の非インタラクティブ出力を維持する:

- `--json` フラグ指定時
- stdout が TTY でない時（`!stdout.isTty()`）

`-l`、`-p`、`--docker` フラグはインタラクティブモードと併用可能（フィルタとして機能）。

---

## テスト方針

- `select.zig` のユニットテストは rawモードを使わず、キーバイト列 → アクションのマッピングのみ検証
- 画面描画は統合テスト or 手動確認

---

## 対象外

- 複数選択（1つを選んでkillが今回のスコープ）
- SIGKILL などシグナル選択（SIGTERM固定）
- スクロール（エントリが画面に収まる前提）
