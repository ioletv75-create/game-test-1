extends Node
## 游戏主控：生成小怪、计分、开局/结束流程。
## 分数只来自"吃鱼"：吃掉 power 为 p 的鱼得 p × 10 分。

@export var mob_scene: PackedScene

@export_group("小怪生成")
## 小怪 power 的取值区间（1.0 = 基准体型）
@export var power_min: float = 0.35
@export var power_max: float = 2.4
## 分布偏斜：越大越偏向生成小鱼（1.0 = 均匀）
@export_range(1.0, 4.0, 0.1) var power_bias: float = 1.6
## 小怪基准速度区间（像素/秒），实际速度还会按体型修正
@export var speed_min: float = 400.0
@export var speed_max: float = 500.0
## 每单位 power 折算的分数
@export var score_per_power: float = 10.0

@export_group("音效")
## 吃鱼音效的截断时长（秒）。<= 0 表示整段播完（短视频直接这样用最省事）
@export var eat_sfx_time: float = 0.0
## 截断时的收尾淡出时长（秒），仅当 eat_sfx_time > 0 才生效
@export var eat_sfx_fade: float = 0.12

@export_group("难度曲线")
## 每过多少秒收紧一次刷怪节奏（<=0 表示不随时间变难）
@export var ramp_interval: float = 15.0
## 每次收紧的比例（0.92 = 间隔缩短 8%）
@export var ramp_factor: float = 0.92
## 刷怪间隔下限（秒），再难也不会快过这个
@export var min_mob_wait: float = 0.16

var score := 0
var best_score := 0

var running := false

var _eat_sfx_tween: Tween
var _eat_base_db := -4.0
var _base_mob_wait := 0.4
var _elapsed := 0.0
var _next_ramp := 0.0

## 最高分存档路径（测试时可改到 res:// 下临时文件）
var save_path := "user://best_score.cfg"

@onready var player: Area2D = $Player
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	# P0 的关键修复：玩家的 hit 信号以前连到一个空函数，游戏永远结束不了。
	player.hit.connect(game_over)
	player.ate.connect(_on_player_ate)
	hud.start_game.connect(new_game)
	_eat_base_db = $EatSound.volume_db
	_base_mob_wait = $MobTimer.wait_time
	_load_best()
	_setup_bgm()
	new_game()


func _process(delta: float) -> void:
	if not running or ramp_interval <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= _next_ramp:
		_next_ramp += ramp_interval
		_tighten_spawn()


func new_game() -> void:
	score = 0
	running = true
	_elapsed = 0.0
	_next_ramp = ramp_interval
	$MobTimer.wait_time = _base_mob_wait
	_clear_mobs()
	$GameOverSound.stop()
	hud.reset(score, best_score)
	player.start($StartPosition.position)
	hud.update_power(player.power)
	$MobTimer.stop()
	$StartTimer.start()


func game_over() -> void:
	if not running:
		return
	running = false
	$StartTimer.stop()
	$MobTimer.stop()
	_clear_mobs()
	$GameOverSound.play()

	# 结算：破纪录才写存档
	var new_record := score > best_score
	if new_record:
		best_score = score
		_save_best()
	hud.show_game_over(score, best_score, new_record)


func _load_best() -> void:
	best_score = 0
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	best_score = int(cfg.get_value("score", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("最高分保存失败(%s): %s" % [save_path, error_string(err)])


## 难度曲线：每隔 ramp_interval 秒把刷怪间隔乘以 ramp_factor，直到下限
func _tighten_spawn() -> void:
	var mob_timer: Timer = $MobTimer
	mob_timer.wait_time = maxf(mob_timer.wait_time * ramp_factor, min_mob_wait)


## 背景音乐：循环 + 一直播（不随开局/结束重置）
func _setup_bgm() -> void:
	var bgm: AudioStreamPlayer = $BGM
	if bgm.stream == null:
		return
	# MP3/OGG 的循环开关挂在「流资源」上，不是在播放器上
	if "loop" in bgm.stream:
		bgm.stream.set("loop", true)
	if not bgm.playing:
		bgm.play()


## 吃鱼音效：从头播，播到 eat_sfx_time 就淡出收掉
func _play_eat_sound() -> void:
	var eat: AudioStreamPlayer = $EatSound
	if eat.stream == null:
		return
	if _eat_sfx_tween != null and _eat_sfx_tween.is_valid():
		_eat_sfx_tween.kill()
	eat.volume_db = _eat_base_db
	eat.play()
	if eat_sfx_time <= 0.0:
		return  # 整段播完，不截断也不淡出
	_eat_sfx_tween = create_tween()
	_eat_sfx_tween.tween_interval(maxf(eat_sfx_time - eat_sfx_fade, 0.0))
	_eat_sfx_tween.tween_property(eat, "volume_db", -40.0, eat_sfx_fade)
	_eat_sfx_tween.tween_callback(eat.stop)


func _clear_mobs() -> void:
	for mob in get_tree().get_nodes_in_group("mobs"):
		mob.queue_free()


func _on_player_ate(mob_power: float) -> void:
	score += int(round(mob_power * score_per_power))
	hud.update_score(score)
	hud.update_power(player.power)
	_play_eat_sound()


func _on_mob_timer_timeout() -> void:
	if not running:
		return

	# Create a new instance of the Mob scene.
	var mob = mob_scene.instantiate()

	# 体型：在区间内偏斜采样，power 越大鱼越大、越慢
	mob.power = _roll_mob_power()
	mob.prepare()  # 先算好体型，才能按半径把出生点推到屏幕外

	# Choose a random location on Path2D.
	var mob_spawn_location = $MobPath/MobSpawnLocation
	mob_spawn_location.progress_ratio = randf()

	# 注意：PathFollow2D.position 是 MobPath 的「局部坐标」（x 只有 0~480），
	# 必须用 global_position，否则小怪会全挤在屏幕左半边。
	var spawn_point: Vector2 = mob_spawn_location.global_position
	# 边界指向屏幕内部的法线
	var inward: Vector2 = Vector2.RIGHT.rotated(mob_spawn_location.rotation + PI / 2)

	# 沿法线把出生点往屏幕外推，保证整条鱼都在画面外再游进来
	mob.position = spawn_point - inward * (mob.get_visual_radius() + 8.0)

	# 游进来的方向是法线 ± 45° 的随机偏移
	var direction: float = inward.angle() + randf_range(-PI / 4.0, PI / 4.0)
	mob.rotation = direction

	# Choose the velocity for the mob.
	var speed: float = randf_range(speed_min, speed_max) * mob.get_speed_multiplier()
	mob.linear_velocity = Vector2.RIGHT.rotated(direction) * speed

	# Spawn the mob by adding it to the Main scene.
	add_child(mob)


## 在 [power_min, power_max] 内按 bias 偏斜采样：bias 越大越容易抽到小鱼
func _roll_mob_power() -> float:
	var t: float = pow(randf(), power_bias)
	return lerpf(power_min, power_max, t)


func _on_start_timer_timeout() -> void:
	if not running:
		return
	$MobTimer.start()
