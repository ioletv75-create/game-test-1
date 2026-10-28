extends Area2D
## 玩家（大鱼）。
##
## 尺寸轴：power = 1.0 是初始体型，越大越强、外观越大。
## 碰到小怪时的唯一判定：
##   |Δpower| < 容差带      -> 平手，互相无视，小怪被弹开
##   power > mob.power      -> 吃掉：涨体型 + 得分
##   否则                    -> 被吃：游戏结束（吃鱼后的短暂无敌窗口内不受伤）

signal hit
signal ate(mob_power: float)

@export var speed: float = 400.0

@export_group("体型")
@export var power: float = 1.0
@export var power_max: float = 3.0
## 吃掉 power 为 p 的鱼，体型涨 p * 该系数
@export var eat_grow_ratio: float = 0.15
## 体型长大时视觉过渡时长（秒）—— 吃鱼很快，所以给得很短
@export var grow_time: float = 0.12
## 平手容差带：差值 < max(peer_band_min, 较大者 * peer_band_ratio) 视为同尺寸
@export var peer_band_ratio: float = 0.08
@export var peer_band_min: float = 0.1

@export_group("吃鱼手感")
## 吃掉一条鱼之后的短暂无敌时间（秒）
@export var eat_invuln_time: float = 0.3
## eat 动作的持续时长（秒）。吃鱼很快，所以很短；动画本身只有 1 帧，
## 靠这个计时器撑住，不依赖帧率。
@export var eat_anim_time: float = 0.2
## 无敌期间贴在精灵上的高光色（>1 的分量会把鱼提亮，一眼看出"现在撞不死"）
@export var invuln_tint: Color = Color(1.35, 1.45, 1.7)

const EAT_ANIM := "eat"

var screen_size := Vector2.ZERO
var dead := false

var _frame_size := Vector2.ZERO
var _base_sprite_scale := 0.9
var _base_capsule_radius := 0.0
var _base_capsule_height := 0.0
var _visual_factor := 1.0
var _invuln_left := 0.0
var _eat_left := 0.0
var _grow_tween: Tween = null


func _ready() -> void:
	screen_size = get_viewport_rect().size
	_base_sprite_scale = $AnimatedSprite2D.scale.x

	# 形状资源在场景里是共用的，先复制一份再改，免得多开一局时互相污染
	var shape: Shape2D = $CollisionShape2D.shape
	if shape != null:
		shape = shape.duplicate()
		$CollisionShape2D.shape = shape
		if shape is CapsuleShape2D:
			_base_capsule_radius = shape.radius
			_base_capsule_height = shape.height

	_frame_size = _get_frame_size()
	_apply_body_scale(1.0)

	# 场景文件里原本没连 body_entered，玩家永远不会死；这里用代码连，改节点名也不会断
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(0.0, _invuln_left - delta)
	_update_invuln_tint()

	if dead:
		return

	_tick_eat_state(delta)

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var velocity := _read_input()

	if velocity != Vector2.ZERO:
		velocity = velocity.normalized() * speed
		if _eat_left > 0.0:
			# 吃的时候保持 eat 姿势，但照样能转身
			if velocity.x != 0.0:
				sprite.flip_h = velocity.x < 0.0
		else:
			_play_move_anim(velocity)
		# 注意：AnimatedSprite2D.play() 会把帧重置到 0，
		# 每帧无条件调用会让动画永远停在第一帧，所以要先判 is_playing()。
		if not sprite.is_playing():
			sprite.play()
	elif _eat_left <= 0.0:
		sprite.stop()

	position += velocity * delta
	_clamp_to_screen()

	_resolve_contacts()


#region eat 动作
## eat 姿势只撑 eat_anim_time 这段时间，到点立刻回到移动动画，
## 哪怕人站着不动也不会卡在 eat 帧上。
func _tick_eat_state(delta: float) -> void:
	if _eat_left <= 0.0:
		return
	_eat_left = maxf(0.0, _eat_left - delta)
	if _eat_left == 0.0:
		_set_animation("walk")


func _play_eat_frame() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(EAT_ANIM):
		return
	sprite.animation = EAT_ANIM
	sprite.frame = 0
	sprite.play()
	_frame_size = _get_frame_size()


func _update_invuln_tint() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.modulate = invuln_tint if _invuln_left > 0.0 else Color.WHITE
#endregion


func _read_input() -> Vector2:
	var velocity := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		velocity.x += 1.0
	if Input.is_action_pressed("move_left"):
		velocity.x -= 1.0
	if Input.is_action_pressed("move_down"):
		velocity.y += 1.0
	if Input.is_action_pressed("move_up"):
		velocity.y -= 1.0
	return velocity


#region 尺寸判定
## 每物理帧结算一次接触：吃 / 被吃。
## 用「重叠检测」而不是只靠 body_entered，是为了让「无敌窗口结束时人还贴在大鱼身上」
## 这种情况也能正确判定，不会变成永久免死。
func _resolve_contacts() -> void:
	for body in get_overlapping_bodies():
		if dead:
			return
		if not body.has_method("be_eaten"):
			continue
		var mob_power: float = body.power
		if _is_peer(mob_power):
			continue
		if power > mob_power:
			_eat(body, mob_power)
			return
		if _invuln_left <= 0.0:
			die()
			return


## 只在「刚接触」时把平手的小怪弹开一次，避免每帧重复推
func _on_body_entered(body: Node) -> void:
	if dead:
		return
	if not body.has_method("be_eaten"):
		die()  # 不是小怪（以后加的障碍物等）按原来的规则处理
		return
	if _is_peer(body.power):
		body.push_away(global_position)


## 体型接近 -> 谁也吃不掉谁
func _is_peer(mob_power: float) -> bool:
	var band := maxf(peer_band_min, maxf(power, mob_power) * peer_band_ratio)
	return absf(power - mob_power) < band


func _eat(mob: Node, mob_power: float) -> void:
	mob.be_eaten()
	_grow(mob_power * eat_grow_ratio)
	_invuln_left = eat_invuln_time
	# 已经在吃的时候不重播动画（会抽搐），只把无敌窗口刷新一下
	if _eat_left <= 0.0:
		_eat_left = eat_anim_time
		_play_eat_frame()
	ate.emit(mob_power)
#endregion


#region 成长
func _grow(amount: float) -> void:
	var target := minf(power + amount, power_max)
	if target <= power:
		return
	power = target

	if _grow_tween != null and _grow_tween.is_valid():
		_grow_tween.kill()
	_grow_tween = create_tween()
	_grow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_grow_tween.tween_method(_apply_body_scale, _visual_factor, target, grow_time)


## 把"体型倍数"同时作用到精灵缩放和碰撞体上（碰撞体不跟着长，长大后判定会停在原大小）
func _apply_body_scale(factor: float) -> void:
	_visual_factor = factor

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.scale = Vector2.ONE * (_base_sprite_scale * factor)

	var shape: Shape2D = $CollisionShape2D.shape
	if shape is CapsuleShape2D:
		shape.radius = _base_capsule_radius * factor
		shape.height = _base_capsule_height * factor
#endregion


#region 移动动画
func _play_move_anim(velocity: Vector2) -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if velocity.x != 0.0:
		_set_animation("walk")
		sprite.flip_h = velocity.x < 0.0
	elif velocity.y != 0.0:
		_set_animation("up")
		# 俯视角的鱼不做垂直翻转，只保留左右翻转
		sprite.flip_h = false


func _set_animation(anim_name: String) -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		return
	if sprite.animation != anim_name:
		sprite.animation = anim_name
		_frame_size = _get_frame_size()


func _get_frame_size() -> Vector2:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.sprite_frames == null:
		return Vector2.ZERO
	var anim_name := sprite.animation
	if not sprite.sprite_frames.has_animation(anim_name):
		return Vector2.ZERO
	if sprite.sprite_frames.get_frame_count(anim_name) == 0:
		return Vector2.ZERO
	var texture := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if texture == null:
		return Vector2.ZERO
	return texture.get_size()


## 玩家在屏幕上的实际半尺寸（贴图尺寸 × 精灵缩放 × 节点缩放 ÷ 2）
func get_visual_half_size() -> Vector2:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	return (_frame_size * sprite.scale * scale) * 0.5


func _clamp_to_screen() -> void:
	var half := get_visual_half_size()
	var min_pos := half
	var max_pos := screen_size - half
	max_pos.x = maxf(max_pos.x, min_pos.x)
	max_pos.y = maxf(max_pos.y, min_pos.y)
	position = position.clamp(min_pos, max_pos)
#endregion


func die() -> void:
	if dead:
		return
	dead = true
	hide()
	hit.emit()
	# 物理回调里不能直接改碰撞属性，必须 deferred
	$CollisionShape2D.set_deferred("disabled", true)
	set_deferred("monitoring", false)


func start(pos: Vector2) -> void:
	dead = false
	_invuln_left = 0.0
	_eat_left = 0.0
	$AnimatedSprite2D.modulate = Color.WHITE

	power = 1.0
	if _grow_tween != null and _grow_tween.is_valid():
		_grow_tween.kill()
	_apply_body_scale(1.0)

	position = pos
	show()
	$AnimatedSprite2D.stop()
	$AnimatedSprite2D.animation = "walk"
	_frame_size = _get_frame_size()
	$CollisionShape2D.set_deferred("disabled", false)
	set_deferred("monitoring", true)
