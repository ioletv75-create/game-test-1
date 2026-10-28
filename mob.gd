extends RigidBody2D
## 小怪。
##
## power = 体型档位：1.0 是基准，>1 更大更凶，<1 更小更好吃。
## 精灵缩放、碰撞圆、屏幕外回收框全部从 power 推导 —— 不要手动改场景里
## AnimatedSprite2D 的 scale，否则会被 _apply_size() 覆盖掉。

const MOB_GROUP := "mobs"
const BASE_SPRITE_SCALE := 0.07  # power = 1.0 时的精灵缩放（沿用原场景数值）

@export var power: float = 1.0:
	set(value):
		power = value
		if is_inside_tree():
			_apply_size()

## 碰撞圆半径 = 视觉短边的一半 × 该系数（1.0 刚好贴住图形，太小会"鬼穿模"）
@export var collision_ratio: float = 0.9
## 大鱼游得慢、小鱼游得快
@export var big_is_slower: bool = true

var _visual_radius := 0.0
var _prepared := false


func _ready() -> void:
	add_to_group(MOB_GROUP)
	if not _prepared:
		prepare()


## 由 Main 在 add_child 之前调用：提前算好体型，
## 好让主控能按"整条鱼多大"把它放到屏幕外面去。
func prepare() -> void:
	if _prepared:
		return
	_pick_animation()
	_apply_size()
	_prepared = true


## 视觉半径（像素），主控用来把出生点推到屏幕外
func get_visual_radius() -> float:
	return _visual_radius


func _pick_animation() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var anim_names := Array(sprite.sprite_frames.get_animation_names())
	sprite.animation = anim_names.pick_random()
	sprite.play()


func _apply_size() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var factor := clampf(power, 0.2, 4.0)
	var sprite_scale := BASE_SPRITE_SCALE * factor
	sprite.scale = Vector2(sprite_scale, sprite_scale)

	var visual_size := _get_frame_size() * sprite_scale

	# 鱼会随移动方向旋转，所以半径按"短边"算；按长边算会横着穿模
	var short_side := minf(visual_size.x, visual_size.y)
	var radius := maxf(short_side * 0.5 * collision_ratio, 4.0)
	_visual_radius = short_side * 0.5  # 到图形外缘的距离（给出生点用）

	var circle := CircleShape2D.new()
	circle.radius = radius
	$CollisionShape2D.shape = circle
	$CollisionShape2D.rotation = 0.0

	# 出屏回收的判定框跟着体型走，否则大鱼还没出屏就被回收
	$VisibleOnScreenNotifier2D.rect = Rect2(-visual_size * 0.5, visual_size)

	mass = 1.0 + factor


## 体型对速度的修正：power 1.0 -> 1.0 倍；0.5 -> 1.41 倍；2.0 -> 0.71 倍
func get_speed_multiplier() -> float:
	if not big_is_slower:
		return 1.0
	return clampf(1.0 / sqrt(maxf(power, 0.05)), 0.5, 1.8)


## 被玩家吃掉
func be_eaten() -> void:
	queue_free()


## 体型差不多时被玩家撞开（不给伤害，只弹出去）
## body_entered 在物理步内触发，直接改速度会被本步覆盖，所以走 deferred。
func push_away(from_global_pos: Vector2) -> void:
	var dir := global_position - from_global_pos
	if dir.length_squared() < 1.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	dir = dir.normalized()
	set_deferred("linear_velocity", linear_velocity + dir * 320.0)


func _get_frame_size() -> Vector2:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.sprite_frames == null:
		return Vector2(100.0, 100.0)
	var anim_name := sprite.animation
	if not sprite.sprite_frames.has_animation(anim_name):
		return Vector2(100.0, 100.0)
	if sprite.sprite_frames.get_frame_count(anim_name) == 0:
		return Vector2(100.0, 100.0)
	var texture := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if texture == null:
		return Vector2(100.0, 100.0)
	return texture.get_size()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
