class_name BossDrone
extends Area3D

signal destroyed(radius : float)

@export var boost_horizontal : float = 9.0
@export var boost_vertical : float = 16.0

var center : Vector3 = Vector3.ZERO
var radius : float = 20.0
var angle : float = 0.0
var dir : float = 1.0
var speed_scale : float = 0.25
var base_y : float = 4.0
var player : CharacterBody3D

var _t : float = 0.0
var _dead : bool = false

func _ready() -> void:
	add_to_group("boss_drones")
	body_entered.connect(_on_body_entered)
	_update_pos()

func _physics_process(delta: float) -> void:
	_t += delta
	angle += dir * speed_scale * delta
	_update_pos()

func _update_pos() -> void:
	global_position = Vector3(
		center.x + cos(angle) * radius,
		base_y + sin(_t * 2.0) * 0.4,
		center.z + sin(angle) * radius)

func _on_body_entered(body: Node3D) -> void:
	if _dead or body != player:
		return
	var stomped : bool = ("is_stomping" in player and player.is_stomping) or player.velocity.y < -6.0
	if not stomped:
		return
	_dead = true
	var to_center : Vector3 = center - player.global_position
	to_center.y = 0.0
	player.velocity = to_center.normalized() * boost_horizontal + Vector3.UP * boost_vertical
	if "is_stomping" in player:
		player.is_stomping = false
	destroyed.emit(radius)
	queue_free()
