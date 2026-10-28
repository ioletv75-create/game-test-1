# 大鱼吃小鱼（Fish Eat Fish）

用 **Godot 4.7** 做的俯视角「吞吃成长」小游戏：吃掉比自己小的鱼，躲开比自己大的鱼，越吃越大。

## 玩法

- 方向键 / WASD 移动
- 吃掉比自己小的鱼 → 体型变大 + 得分
- 撞到比自己大的鱼 → 游戏结束
- 体型接近的鱼（差值 < 8%）互相弹开，互不伤害
- 吃鱼后有约 0.3 秒无敌窗口，鱼身会发亮

## 核心机制

| 机制 | 实现位置 | 说明 |
|---|---|---|
| 体型轴 `power` | `player.gd` / `mob.gd` | 所有判定都收敛到 `player.power > mob.power` 这一次比较 |
| 小怪体型 | `mob.gd::_apply_size()` | 精灵缩放、碰撞圆半径、出屏回收框、质量全部由 `power` 推导 |
| 吃鱼动作 | `player.gd::_tick_eat_state()` | `eat` 姿势由计时器驱动（0.2s），不打断移动，连吃不重播 |
| 难度曲线 | `main.gd::_tighten_spawn()` | 刷怪间隔每 15 秒 ×0.92，下限 0.16s |
| 最高分 | `main.gd::_save_best()` | 存 `user://best_score.cfg` |

## 运行

1. 用 Godot **4.7** 打开本目录
2. 按 F5

## 导出

`export_presets.cfg` 已配好 Windows Desktop 预设。

> 注意：`build/` 已被 `.gitignore` 排除 —— 导出的 exe 有 170MB+，超过 GitHub 100MB 单文件上限。

## 目录结构

```
├── main.gd / main.tscn     主控：刷怪、计分、难度、音频、结算流程
├── player.gd / player.tscn 玩家：移动、体型成长、吃/被吃判定、eat 动作
├── mob.gd / mob.tscn       小怪：体型推导、被吃、平手弹开
├── hud.gd / hud.tscn       分数 / 体型 / 最高分 + Game Over 结算面板
├── art/                    美术与音频（玩家三张立绘、小怪、BGM、音效）
├── fonts/                  Xolonium 字体
└── export_presets.cfg      Windows Desktop 导出配置
```

## 可调参数（都在检查器里）

- `Main` → 小怪生成：`power_min/max`、`power_bias`、速度区间、`score_per_power`
- `Main` → 音效：`eat_sfx_time`（0 = 整段播完）、`eat_sfx_fade`
- `Main` → 难度曲线：`ramp_interval`、`ramp_factor`、`min_mob_wait`
- `Player` → 体型：`power_max`、`eat_grow_ratio`、`grow_time`、容差带
- `Player` → 吃鱼手感：`eat_invuln_time`、`eat_anim_time`、`invuln_tint`

## 已知说明

- 背景音乐是 MP3 循环，个别情况下循环接缝会有极短停顿，转成 OGG 可根治
- 玩家三张立绘已统一到 1600×1600 画布，直接替换 `art/player_*.png` 即可保持动作切换时大小一致
