class_name Shockwave
extends Node3D

var speed : float = 16.0
var max_radius : float = 65.0
var thickness : float = 1.6
var hit_height : float = 1.6   # acima disso o jogador "pulou" a onda
var knockback : float = 14.0
var player : CharacterBody3D

var radius : float = 0.5
var _torus : TorusMesh
var _hit : bool = false

func _ready() -> void:
	_torus = TorusMesh.new()
	var m := MeshInstance3D.new()
	m.mesh = _torus
	m.scale.y = 0.35
	m.position.y = 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.5, 0.1)
	mat.emission_energy_multiplier = 3.0
	m.material_override = mat
	add_child(m)
	_update_mesh()

func _physics_process(delta: float) -> void:
	radius += speed * delta
	if radius > max_radius:
		queue_free()
		return
	_update_mesh()
	_check_player()

func _update_mesh() -> void:
	_torus.inner_radius = maxf(radius - thickness * 0.5, 0.01)
	_torus.outer_radius = radius + thickness * 0.5

func _check_player() -> void:
	if _hit or not player:
		return
	var off : Vector3 = player.global_position - global_position
	var flat := Vector2(off.x, off.z)
	if absf(flat.length() - radius) > thickness or off.y > hit_height:
		return
	_hit = true
	var dir := Vector3(flat.x, 0.0, flat.y).normalized()
	player.velocity = dir * knockback + Vector3.UP * 8.0
