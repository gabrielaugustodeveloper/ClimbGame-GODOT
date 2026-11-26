extends Node3D

@export_group("Boss Settings")
@export var max_hp : int = 3
@export var rotation_speed : float = 1.2
@export var slam_cooldown : float = 3.0
@export var stunned_duration : float = 5.5
@export var windup_time : float = 1.0
@export var slam_angle : float = 45.0     # asin(altura do ombro / comprimento do braço)
@export var windup_angle : float = -50.0

@export_group("Arena")
@export var floor_y : float = 0.0
@export var launch_radius : float = 50.0  # onde o jogador cai ao ser lançado
@export var drone_scene : PackedScene

@export_group("Nodes")
@export var player : CharacterBody3D
@export var arms : Array[Node3D]
@export var head_core_area : Area3D
@export var core_mesh : MeshInstance3D
@export var hp_bar : ProgressBar

enum S { TRACKING, WINDUP, SLAMMED, RECOVERING, DEFEATED }
const DRONE_RADII : Array[float] = [35.0, 35.0, 29.0, 29.0, 23.0, 23.0, 17.0, 17.0]

var state : S = S.TRACKING
var hp : int
var timer : float = 0.0
var arm_index : int = 0
var active_arm : Node3D
var hits : int = 0
var wave_speed : float = 16.0
var double_wave : bool = false
var drone_speed : float = 0.25

func _ready() -> void:
	hp = max_hp
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if head_core_area:
		head_core_area.body_entered.connect(_on_core_body_entered)
	timer = slam_cooldown
	for r in DRONE_RADII:
		_spawn_drone(r)

func _physics_process(delta: float) -> void:
	if state == S.DEFEATED:
		return
	timer -= delta
	match state:
		S.TRACKING:
			_face_player(delta, rotation_speed)
			_rest_arms(delta)
			if timer <= 0.0:
				active_arm = arms[arm_index]
				arm_index = (arm_index + 1) % arms.size()
				state = S.WINDUP
				timer = windup_time
		S.WINDUP:
			_face_player(delta, rotation_speed * 0.3)
			_rest_arms(delta, active_arm)
			_tilt(active_arm, windup_angle, 6.0, delta)
			if timer <= 0.0:
				state = S.SLAMMED
				timer = stunned_duration
				_slam()
		S.SLAMMED:
			# Braço cravado na ilha = rampa para escalar. O boss não gira nesse tempo.
			_tilt(active_arm, slam_angle, 16.0, delta)
			_rest_arms(delta, active_arm)
			if timer <= 0.0:
				state = S.RECOVERING
				timer = 1.2
		S.RECOVERING:
			_rest_arms(delta)
			if timer <= 0.0:
				state = S.TRACKING
				timer = slam_cooldown

func _tilt(arm: Node3D, target: float, speed: float, delta: float) -> void:
	if arm:
		arm.rotation_degrees.x = lerpf(arm.rotation_degrees.x, target, speed * delta)

func _rest_arms(delta: float, except: Node3D = null) -> void:
	for a in arms:
		if a != except:
			_tilt(a, 0.0, 4.0, delta)

func _face_player(delta: float, speed: float) -> void:
	if not player:
		return
	var d : Vector3 = player.global_position - global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), speed * delta)

# ---------- Ataques ----------
func _slam() -> void:
	_spawn_wave()
	if double_wave:
		await get_tree().create_timer(0.7).timeout
		if state != S.DEFEATED:
			_spawn_wave()

func _spawn_wave() -> void:
	var w := Shockwave.new()
	w.speed = wave_speed
	w.player = player
	get_parent().add_child(w)
	w.global_position = Vector3(global_position.x, floor_y, global_position.z)

# ---------- Drones ----------
func _spawn_drone(radius: float) -> void:
	if not drone_scene:
		return
	var d : BossDrone = drone_scene.instantiate()
	d.center = global_position
	d.radius = radius
	d.angle = randf() * TAU
	d.dir = 1.0 if randf() > 0.5 else -1.0
	d.speed_scale = drone_speed
	d.base_y = floor_y + 3.0 + randf() * 2.0
	d.player = player
	d.destroyed.connect(_on_drone_destroyed)
	get_parent().add_child.call_deferred(d)

func _on_drone_destroyed(radius: float) -> void:
	await get_tree().create_timer(4.0).timeout
	if state != S.DEFEATED:
		_spawn_drone(radius)

# ---------- Dano ----------
func _on_core_body_entered(body: Node3D) -> void:
	if body != player or state == S.DEFEATED:
		return
	var stomp : bool = ("is_stomping" in player and player.is_stomping) or player.velocity.y < -8.0
	if stomp:
		_take_damage()

func _take_damage() -> void:
	hp -= 1
	hits += 1
	if hp_bar:
		hp_bar.value = hp
	_launch_player_to_outer_ring()
	_flash_core()
	if hp <= 0:
		_defeat()
	else:
		_apply_difficulty()
		state = S.RECOVERING
		timer = 1.5

func _launch_player_to_outer_ring() -> void:
	if "is_stomping" in player:
		player.is_stomping = false
	var away : Vector3 = player.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	var target : Vector3 = global_position + away * launch_radius
	target.y = floor_y + 1.0
	var T : float = 2.4  # tempo de voo
	var g : float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var d : Vector3 = target - player.global_position
	player.velocity = Vector3(d.x / T, d.y / T + 0.5 * g * T, d.z / T)

func _apply_difficulty() -> void:
	slam_cooldown = maxf(1.2, slam_cooldown - 0.6)
	wave_speed += 4.0
	double_wave = hits >= 2
	drone_speed += 0.12
	get_tree().call_group("boss_drones", "set", "speed_scale", drone_speed)

func _flash_core() -> void:
	if core_mesh and core_mesh.get_active_material(0) is BaseMaterial3D:
		var mat : BaseMaterial3D = core_mesh.get_active_material(0)
		mat.emission_energy_multiplier = 8.0
		await get_tree().create_timer(0.25).timeout
		if is_instance_valid(mat):
			mat.emission_energy_multiplier = 1.5

func _defeat() -> void:
	state = S.DEFEATED
	get_tree().call_group("boss_drones", "queue_free")
	if head_core_area:
		head_core_area.visible = false
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 12.0, 2.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
