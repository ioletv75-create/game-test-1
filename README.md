# 大鱼吃小鱼（Fish Eat Fish）

用 **Godot 4.7** 做的俯视角「吞吃成长」小游戏：吃掉比自己小的鱼，躲开比自己大的鱼，越吃越大。

## 玩法

- 方向键 / WASD 移动
- 吃掉比自己小的鱼 → 体型变大 + 得分
- 撞到比自己大的鱼 → 游戏结束
- 体型接近的鱼（差值 < 8%）互相弹开，互不伤害
- 吃鱼后有约 0.3 秒无敌窗口，鱼身会发亮

## 项目结构

```
game-test-1/
├── project.godot              Godot 项目配置（需 Godot 4.7）
├── scenes/                    场景
│   ├── main.tscn              主场景（游戏本体）
│   ├── player.tscn            玩家
│   ├── mob.tscn               小怪
│   └── hud.tscn               分数 / 提示 / 结算面板
├── scripts/                   脚本
│   ├── main.gd                主控：刷怪、计分、难度曲线、音频、结算流程
│   ├── player.gd              玩家：移动、体型成长、吃与被吃判定、eat 动作
│   ├── mob.gd                 小怪：体型推导、被吃、平手弹开
│   └── hud.gd                 分数 / 体型 / 最高分 / Game Over 面板
├── assets/
│   ├── sprites/               游戏用图：玩家 3 张立绘 + 小怪 4 张
│   ├── audio/                 背景音乐 + 吃鱼音效 + 死亡音效
│   ├── fonts/                 Xolonium 字体（含 OFL 授权原文）
│   └── source/                未参与运行的原图（玩家立绘源文件，供重新裁切用）
├── export_presets.cfg         Windows Desktop 导出配置
├── LICENSE                    MIT
└── README.md
```

## 核心机制

| 机制 | 实现位置 | 说明 |
|---|---|---|
| 体型轴 `power` | `scripts/player.gd`、`scripts/mob.gd` | 所有判定都收敛到 `player.power > mob.power` 这一次比较 |
| 小怪体型 | `mob.gd::_apply_size()` | 精灵缩放、碰撞圆半径、出屏回收框、质量全部由 `power` 推导 |
| 吃鱼动作 | `player.gd::_tick_eat_state()` | `eat` 姿势由计时器驱动（0.2s），不打断移动，连吃不重播 |
| 平手容差带 | `player.gd::_is_peer()` | 差值 < `max(0.1, 较大者 × 0.08)` 视为同尺寸，互相弹开 |
| 难度曲线 | `main.gd::_tighten_spawn()` | 刷怪间隔每 15 秒 ×0.92，下限 0.16s |
| 最高分 | `main.gd::_save_best()` | 存 `user://best_score.cfg` |

## 运行

1. 用 **Godot 4.7** 打开本目录
2. 按 **F5**

## 导出

`export_presets.cfg` 已配好 Windows Desktop 预设，导出输出到 `build/`。

> `build/` 已被 `.gitignore` 排除 —— 导出的 exe 有 170MB+，超过 GitHub 100MB 单文件上限。

## 可调参数（都在检查器里）

- `Main` → **小怪生成**：`power_min/max`、`power_bias`、速度区间、`score_per_power`
- `Main` → **音效**：`eat_sfx_time`（0 = 整段播完）、`eat_sfx_fade`
- `Main` → **难度曲线**：`ramp_interval`、`ramp_factor`、`min_mob_wait`
- `Player` → **体型**：`power_max`、`eat_grow_ratio`、`grow_time`、容差带
- `Player` → **吃鱼手感**：`eat_invuln_time`、`eat_anim_time`、`invuln_tint`

## 授权 / License

| 内容 | 授权 |
|---|---|
| 代码（`scripts/*.gd`）、场景（`scenes/*.tscn`）、项目配置 | **MIT**，见 [`LICENSE`](LICENSE) |
| 字体 Xolonium | SIL Open Font License 1.1，见 [`assets/fonts/LICENSE.txt`](assets/fonts/LICENSE.txt) |
| 立绘（`assets/sprites/*.png`、`assets/source/*.png`） | 自制 / 生成素材，随本仓库以 MIT 发布 |
| 音频（`assets/audio/*.mp3`、`gameover.wav`） | ⚠️ **不在 MIT 授权范围内**，版权归各自权利方所有，仅用于学习演示，请勿商用或再分发 |

如果你要基于本项目做自己的游戏，请自行替换上述音频为你有权使用的素材。

## 已知说明

- 背景音乐是 MP3 循环，个别情况下循环接缝会有极短停顿，转成 OGG 可根治
- 玩家三张立绘已统一到 1600×1600 画布（主体视觉面积一致），直接替换 `assets/sprites/player_*.png` 即可保持动作切换时大小不变
- 小怪碰撞用圆形、半径按视觉短边计算（鱼会随移动方向旋转，按长边算会横着穿模）
