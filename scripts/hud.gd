extends CanvasLayer
## HUD：分数 / 体型 / 最高分、开局提示、Game Over 结算面板。

signal start_game

const TITLE := "大鱼吃小鱼"
const HINT := "吃掉比你小的鱼，躲开比你大的！"


func _ready() -> void:
	# 场景里原本一条信号连线都没有，于是：
	#   MessageTimer.timeout 没人接 -> 中间的文字永远不消失（挡住画面）
	#   StartButton.pressed  没人接 -> 死亡后点"开始"毫无反应
	# 统一在这里用代码连，改节点名也不会断。
	var restart: Button = $GameOverPanel/VBox/RestartButton
	if not restart.pressed.is_connected(_on_restart_pressed):
		restart.pressed.connect(_on_restart_pressed)
	if not $MessageTimer.timeout.is_connected(_on_message_timer_timeout):
		$MessageTimer.timeout.connect(_on_message_timer_timeout)


## 开新一局：收起结算面板，只在中间闪一下玩法提示（到点自动隐藏）
func reset(score_value: int, best_value: int) -> void:
	$GameOverPanel.hide()
	update_score(score_value)
	update_best(best_value)
	update_power(1.0)
	show_message("%s\n%s" % [TITLE, HINT])


func show_message(text: String) -> void:
	$Message.text = text
	$Message.show()
	$MessageTimer.start()


## 结算：弹出面板，显示本局得分 / 最高分 / 是否破纪录
func show_game_over(score_value: int, best_value: int, new_record: bool) -> void:
	$Message.hide()
	update_score(score_value)
	update_best(best_value)

	$GameOverPanel/VBox/ResultLabel.text = "得分 %d" % score_value
	$GameOverPanel/VBox/BestResultLabel.text = "最高 %d" % best_value
	$GameOverPanel/VBox/NewRecordLabel.visible = new_record
	$GameOverPanel.show()


func update_score(score_value: int) -> void:
	$ScoreLabel.text = str(score_value)


func update_best(best_value: int) -> void:
	$BestLabel.text = "最高 %d" % best_value


func update_power(power_value: float) -> void:
	$SizeLabel.text = "体型 %.2f" % power_value


func _on_restart_pressed() -> void:
	$GameOverPanel.hide()
	start_game.emit()


func _on_message_timer_timeout() -> void:
	$Message.hide()
