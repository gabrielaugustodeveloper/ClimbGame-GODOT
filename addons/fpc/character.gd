# COPYRIGHT Colormatic Studios
# MIT license
# Updated with Smooth Ledge Mantling, Glitch-Free Wall Jump, Sonic Air Stomp (Ctrl), and 1-Slot Weight Inventory

extends CharacterBody3D

#region Character Export Group
@export_category("Character")
@export var base_speed : float = 4.0
@export var sprint_speed : float = 7.0
@export var crouch_speed : float = 2.0
@export var acceleration : float = 10.0
@export var jump_velocity : float = 5.0
@export var mouse_sensitivity : float = 0.1
@export var invert_camera_x_axis : bool = false
@export var invert_camera_y_axis : bool = false
@export var immobile : bool = false
@export_file var default_reticle

@export_group("Stomp & Mantle Settings")
## Downward speed when pressing Ctrl in mid-air (Sonic Stomp)
@export var stomp_velocity : float = 28.0
## Upward boost when climbing over a ledge
@export var mantle_up_force : float = 7.5
## Forward push onto the platform when climbing over a ledge
@export var mantle_forward_force : float = 6.5

@export_group("Inventory & Weight Settings")
## Base force applied when throwing a light item
@export var throw_force : float = 14.0
## Gentle impulse when simply dropping the item
@export var drop_force : float = 2.0
## Mass threshold for Medium items (above this is Medium, up to Heavy threshold)
@export var medium_mass_threshold : float = 2.0
## Mass threshold for Heavy items (above this is Heavy)
@export var heavy_mass_threshold : float = 7.0
#endregion

#region Nodes Export Group
@export_group("Nodes")
@export var HEAD : Node3D
@export var CAMERA : Camera3D
@export var HEADBOB_ANIMATION : AnimationPlayer
@export var JUMP_ANIMATION : AnimationPlayer
@export var CROUCH_ANIMATION : AnimationPlayer
@export var COLLISION_MESH : CollisionShape3D
@export var WALL_CHECK : RayCast3D
@export var GRAPPLE_CHECK : RayCast3D
@export var INTERACT_CHECK : RayCast3D
@export var INVENTORY_LABEL : Label
#endregion

#region Controls Export Group
@export_group("Controls")
@export var controls : Dictionary = {
	LEFT = "ui_left",
	RIGHT = "ui_right",
	FORWARD = "ui_up",
	BACKWARD = "ui_down",
	JUMP = "ui_accept",
	CROUCH = "crouch",
	SPRINT = "sprint",
	PAUSE = "ui_cancel",
	INTERACT = "interact",
	THROW = "throw_item",
	STOMP = "stomp"
	}
@export_range(0.001, 0.1, 0.001) var look_sensitivity : float = 0.035
#endregion

#region Feature Settings Export Group
@export_group("Feature Settings")
@export var mechanics_enabled : bool = true
@export var jumping_enabled : bool = true
@export var in_air_momentum : bool = true
@export var motion_smoothing : bool = true
@export var sprint_enabled : bool = true
@export var crouch_enabled : bool = true
@export var dynamic_fov : bool = true
@export var continuous_jumping : bool = true
@export var view_bobbing : bool = true
@export var view_tilting : bool = false
@export var jump_animation : bool = true
@export var pausing_enabled : bool = true
@export var gravity_enabled : bool = true
#endregion

#region Variables
var speed : float = base_speed
var current_speed : float = 0.0
var state : String = "normal" # "normal", "crouching", "sprinting", "climbing", "grappling"
var low_ceiling : bool = false
var was_on_floor : bool = true

# Grapple Variables
var grapple_point : Vector3 = Vector3.ZERO
var is_grapple_attached : bool = false
var is_being_pulled : bool = false
var grapple_timer : float = 0.0
const GRAPPLE_COOLDOWN : float = 5.0

# Climbing, Wall-Jump & Mantling Variables
var climb_timer : float = 0.0
var climb_cooldown_timer : float = 0.0
const MAX_CLIMB_TIME : float = 10.0
const CLIMB_COOLDOWN : float = 10.0
var last_wall_normal : Vector3 = Vector3.ZERO
var wall_jump_lock_timer : float = 0.0
var mantle_boost_timer : float = 0.0
var mantle_direction : Vector3 = Vector3.ZERO

# Sonic Stomp Variables
var is_stomping : bool = false
var was_Ctrl_pressed : bool = false

# Single-Slot Inventory & Weight Multipliers
var carried_item : RigidBody3D = null
var weight_speed_mult : float = 1.0
var weight_jump_mult : float = 1.0
var weight_gravity_mult : float = 1.0
var weight_throw_mult : float = 1.0
var current_weight_label : String = ""

var RETICLE : Control
var mouse_input : Vector2 = Vector2(0,0)
var input_dir : Vector2 = Vector2.ZERO
var moving : bool = false
#endregion

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	HEAD.rotation.y = rotation.y
	rotation.y = 0

	if default_reticle:
		change_reticle(default_reticle)

	_initialize_animations()
	_check_controls()
	_enter_normal_state()
	_update_inventory_ui()

func _process(delta : float) -> void:
	if pausing_enabled:
		_handle_pausing()
	_update_debug_menu_per_frame()
	
	if grapple_timer > 0.0: grapple_timer -= delta
	if climb_cooldown_timer > 0.0: climb_cooldown_timer -= delta
	if wall_jump_lock_timer > 0.0: wall_jump_lock_timer -= delta
	if mantle_boost_timer > 0.0: mantle_boost_timer -= delta

func _physics_process(delta : float) -> void:
	_handle_inventory_logic()
	_handle_grappling_logic(delta)
	_handle_climbing_logic(delta)

	if state == "climbing":
		is_stomping = false
		_handle_climbing_movement(delta)
	elif state == "grappling":
		is_stomping = false
		_handle_grappling_movement(delta)
	else:
		# Reset stomp when landing on the floor
		if is_on_floor():
			is_stomping = false
		else:
			_handle_air_stomp()

		# Apply gravity or Stomp velocity
		if not is_on_floor() and gravity_enabled:
			if is_stomping:
				velocity.x = 0.0
				velocity.z = 0.0
				velocity.y = -stomp_velocity
			else:
				velocity += get_gravity() * weight_gravity_mult * delta

		_handle_jumping()

		input_dir = Vector2.ZERO
		if not immobile and not is_stomping:
			input_dir = Input.get_vector(controls.LEFT, controls.RIGHT, controls.FORWARD, controls.BACKWARD)

		moving = input_dir != Vector2.ZERO
		_handle_movement(delta, input_dir)
		_handle_state(moving)

	current_speed = Vector3.ZERO.distance_to(get_real_velocity())
	_handle_head_rotation(delta)

	low_ceiling = $CrouchCeilingDetection.is_colliding()

	if dynamic_fov and state != "climbing" and state != "grappling":
		_update_camera_fov()

	if view_bobbing and state != "grappling":
		_play_headbob_animation(moving or state == "climbing")

	if jump_animation and state != "climbing" and state != "grappling":
		_play_jump_animation()

	_update_debug_menu_per_tick()
	was_on_floor = is_on_floor()

#region Sonic Air Stomp Logic (Press Ctrl in mid-air)
func _handle_air_stomp() -> void:
	var ctrl_down : bool = Input.is_key_pressed(KEY_CTRL)
	var stomp_just_pressed : bool = (ctrl_down and not was_Ctrl_pressed)
	was_Ctrl_pressed = ctrl_down
	
	if InputMap.has_action(controls.STOMP) and Input.is_action_just_pressed(controls.STOMP):
		stomp_just_pressed = true

	# Trigger fast downward stomp if in mid-air and not already stomping
	if stomp_just_pressed and not is_on_floor() and not is_stomping:
		is_stomping = true
		mantle_boost_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = -stomp_velocity
#endregion

#region Single-Slot Inventory & Weight System (Pickup, Drop, Throw, and Mass Calculation)
func _handle_inventory_logic() -> void:
	# Interact key (E): Pickup item if hands are empty, or gently drop if carrying one
	if InputMap.has_action(controls.INTERACT) and Input.is_action_just_pressed(controls.INTERACT):
		if carried_item == null:
			_try_pickup_item()
		else:
			_release_item(drop_force)

	# Throw key (Q): Throw the carried item scaled by its weight
	if InputMap.has_action(controls.THROW) and Input.is_action_just_pressed(controls.THROW):
		if carried_item != null:
			_release_item(throw_force * weight_throw_mult)

func _try_pickup_item() -> void:
	if INTERACT_CHECK and INTERACT_CHECK.is_colliding():
		var collider = INTERACT_CHECK.get_collider()
		if collider is RigidBody3D and collider.is_in_group("pickup"):
			carried_item = collider
			
			# Disable physics and hide object while stored in inventory
			carried_item.freeze = true
			carried_item.visible = false
			for child in carried_item.get_children():
				if child is CollisionShape3D:
					child.disabled = true
			
			_apply_item_weight(carried_item.mass)
			_update_inventory_ui()

func _release_item(impulse_strength : float) -> void:
	if carried_item == null: return
	
	var forward_dir : Vector3 = -CAMERA.global_transform.basis.z.normalized()
	var spawn_pos : Vector3 = CAMERA.global_position + (forward_dir * 1.3)
	
	if INTERACT_CHECK and INTERACT_CHECK.is_colliding():
		var hit_point = INTERACT_CHECK.get_collision_point()
		if CAMERA.global_position.distance_to(hit_point) < 1.5:
			spawn_pos = CAMERA.global_position + (forward_dir * 0.5)
	
	carried_item.global_position = spawn_pos
	carried_item.global_rotation = Vector3.ZERO
	
	for child in carried_item.get_children():
		if child is CollisionShape3D:
			child.disabled = false
	carried_item.visible = true
	carried_item.freeze = false
	
	carried_item.linear_velocity = Vector3.ZERO
	carried_item.angular_velocity = Vector3.ZERO
	
	# Multiply impulse by item mass so RigidBody3D acceleration matches our desired throw distance
	var throw_vector : Vector3 = (forward_dir + Vector3(0, 0.15, 0)).normalized() * (impulse_strength * carried_item.mass)
	carried_item.apply_central_impulse(throw_vector + (velocity * 0.3 * carried_item.mass))
	
	carried_item = null
	_reset_weight_modifiers()
	_update_inventory_ui()

func _apply_item_weight(item_mass : float) -> void:
	# Light Item: No penalty
	if item_mass <= medium_mass_threshold:
		weight_speed_mult = 1.0
		weight_jump_mult = 1.0
		weight_gravity_mult = 1.0
		weight_throw_mult = 1.0
		current_weight_label = "Leve"
	# Medium Item: Slight penalty
	elif item_mass <= heavy_mass_threshold:
		weight_speed_mult = 0.85
		weight_jump_mult = 0.90
		weight_gravity_mult = 1.15
		weight_throw_mult = 0.80
		current_weight_label = "Médio"
	# Heavy Item: Noticeable penalty, but still playable
	else:
		weight_speed_mult = 0.65
		weight_jump_mult = 0.75
		weight_gravity_mult = 1.35
		weight_throw_mult = 0.55
		current_weight_label = "Pesado"

func _reset_weight_modifiers() -> void:
	weight_speed_mult = 1.0
	weight_jump_mult = 1.0
	weight_gravity_mult = 1.0
	weight_throw_mult = 1.0
	current_weight_label = ""

func _update_inventory_ui() -> void:
	if INVENTORY_LABEL:
		if carried_item != null:
			INVENTORY_LABEL.text = "Inventário: [" + carried_item.name + " - " + current_weight_label + "] (E: Largar | Q: Arremessar)"
		else:
			INVENTORY_LABEL.text = "Inventário: [Vazio]"
#endregion

#region Grappling Logic
func _handle_grappling_logic(_delta : float) -> void:
	if not mechanics_enabled: return

	if grapple_timer > 0.0:
		if is_grapple_attached or is_being_pulled:
			is_grapple_attached = false
			is_being_pulled = false
			_enter_normal_state()
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if not is_grapple_attached and GRAPPLE_CHECK and GRAPPLE_CHECK.is_colliding():
			var collider = GRAPPLE_CHECK.get_collider()
			var material_name = collider.name if collider else ""
			
			var grapple_blocked = "Chão" in material_name or "Apenas mão" in material_name
			if not grapple_blocked:
				grapple_point = GRAPPLE_CHECK.get_collision_point()
				is_grapple_attached = true
		
		if is_grapple_attached and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_being_pulled = true
			state = "grappling"
		else:
			if is_being_pulled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				is_being_pulled = false
				state = "normal"
	else:
		if is_grapple_attached or is_being_pulled:
			is_grapple_attached = false
			is_being_pulled = false
			grapple_timer = GRAPPLE_COOLDOWN
			_enter_normal_state()

func _handle_grappling_movement(delta : float) -> void:
	var to_target = grapple_point - global_position
	var distance = to_target.length()
	
	# Grapple pull speed is also slightly affected by heavy weight
	var pull_direction = to_target.normalized()
	var effective_pull_speed = 22.0 * lerpf(1.0, weight_speed_mult, 0.5)
	velocity = velocity.lerp(pull_direction * effective_pull_speed, acceleration * delta)
	
	if distance < 2.0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		is_grapple_attached = false
		is_being_pulled = false
		grapple_timer = GRAPPLE_COOLDOWN
		_enter_normal_state()
		
	move_and_slide()
#endregion

#region Climbing, Glitch-Free Wall Jump & Ledge Mantling Logic
func _handle_climbing_logic(delta : float) -> void:
	if not mechanics_enabled or is_grapple_attached: return

	if climb_cooldown_timer > 0.0:
		if state == "climbing": _enter_normal_state()
		return

	# Prevent instant re-grab right after a wall jump or ledge mantle
	if wall_jump_lock_timer > 0.0:
		return

	var is_holding_left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	if is_holding_left and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if WALL_CHECK and WALL_CHECK.is_colliding():
			var collider = WALL_CHECK.get_collider()
			var material_name = collider.name if collider else ""
			var hit_normal : Vector3 = WALL_CHECK.get_collision_normal()
			
			# If the RayCast hits a flat top surface (normal pointing up) while climbing, trigger Ledge Mantle!
			if state == "climbing" and hit_normal.y > 0.65:
				_trigger_ledge_mantle()
				return
			
			var climbing_forbidden = "Chão" in material_name or "Apenas gancho" in material_name or "Puxável" in material_name
			
			if not climbing_forbidden and abs(hit_normal.y) < 0.65:
				last_wall_normal = hit_normal
				if state != "climbing":
					state = "climbing"
					is_stomping = false
					velocity = Vector3.ZERO
					climb_timer = 0.0
				else:
					# Heavy items drain climbing stamina slightly faster
					climb_timer += delta * weight_gravity_mult
					if climb_timer >= MAX_CLIMB_TIME:
						climb_cooldown_timer = CLIMB_COOLDOWN
						_enter_normal_state()
						return
				
				# Smooth Wall Jump without mid-air re-grab glitch
				if Input.is_action_just_pressed(controls.JUMP):
					wall_jump_lock_timer = 0.35 # Lock climbing for 0.35s so the jump arcs cleanly
					var jump_dir : Vector3 = (last_wall_normal * 1.15 + Vector3.UP * 1.35).normalized()
					velocity = jump_dir * (jump_velocity * weight_jump_mult) * 1.65
					if jump_animation:
						JUMP_ANIMATION.play("jump", 0.25)
					_enter_normal_state()
					return
		elif state == "climbing":
			# When the RayCast clears the top edge of the wall, automatically mantle onto the ledge!
			var raw_input = Input.get_vector(controls.LEFT, controls.RIGHT, controls.FORWARD, controls.BACKWARD)
			if raw_input.y <= 0.1: # Holding W or neutral at the top edge
				_trigger_ledge_mantle()
			else:
				_enter_normal_state()
	else:
		if state == "climbing":
			_enter_normal_state()

func _trigger_ledge_mantle() -> void:
	# Push toward the wall surface (-last_wall_normal) so the player lands squarely on top of the platform
	var into_ledge_dir : Vector3 = -last_wall_normal
	into_ledge_dir.y = 0.0
	if into_ledge_dir.length_squared() < 0.01:
		into_ledge_dir = -HEAD.global_transform.basis.z
		into_ledge_dir.y = 0.0
	into_ledge_dir = into_ledge_dir.normalized()
	
	mantle_direction = into_ledge_dir
	mantle_boost_timer = 0.28 # 0.28s of assisted upward+forward carry over the lip of the wall
	wall_jump_lock_timer = 0.35
	
	velocity = (Vector3.UP * mantle_up_force * weight_jump_mult) + (into_ledge_dir * mantle_forward_force)
	climb_timer = 0.0
	_enter_normal_state()

func _handle_climbing_movement(_delta : float) -> void:
	var normal : Vector3 = last_wall_normal
	if WALL_CHECK and WALL_CHECK.is_colliding():
		normal = WALL_CHECK.get_collision_normal()
		last_wall_normal = normal
		
	var raw_input = Input.get_vector(controls.LEFT, controls.RIGHT, controls.FORWARD, controls.BACKWARD)
	
	var vertical_dir = Vector3.UP * (-raw_input.y)
	var lateral_dir = Vector3.UP.cross(normal).normalized() * raw_input.x
	
	# Slight suction toward the wall (-normal * 1.5) so the character doesn't lose contact on bumpy meshes
	var wall_suction : Vector3 = -normal * 1.5
	var climb_vel : Vector3 = (vertical_dir + lateral_dir).normalized() * (3.5 * weight_speed_mult)
	velocity = climb_vel + wall_suction
	move_and_slide()
	
	# If climbing straight into a step/ledge where the upper raycast still sees wall but top is clear, help step up
	if raw_input.y < -0.1 and is_on_wall() and get_real_velocity().y < 0.3:
		global_position.y += 0.06
#endregion

#region Standard Movement & Controls
func _handle_jumping() -> void:
	if jumping_enabled and state != "climbing" and state != "grappling":
		var effective_jump : float = jump_velocity * weight_jump_mult
		if continuous_jumping:
			if Input.is_action_pressed(controls.JUMP) and is_on_floor() and !low_ceiling:
				if jump_animation: JUMP_ANIMATION.play("jump", 0.25)
				velocity.y += effective_jump
		else:
			if Input.is_action_just_pressed(controls.JUMP) and is_on_floor() and !low_ceiling:
				if jump_animation: JUMP_ANIMATION.play("jump", 0.25)
				velocity.y += effective_jump

func _handle_movement(delta : float, input_dir : Vector2) -> void:
	var direction2D := input_dir.rotated(-HEAD.rotation.y)
	var direction3D := Vector3(direction2D.x, 0, direction2D.y)
	var effective_speed : float = speed * weight_speed_mult
	
	# During ledge mantling, carry the player smoothly forward over the top edge
	if mantle_boost_timer > 0.0:
		velocity.x = mantle_direction.x * mantle_forward_force
		velocity.z = mantle_direction.z * mantle_forward_force
		move_and_slide()
		return

	move_and_slide()

	if is_stomping:
		return

	if in_air_momentum:
		if is_on_floor():
			if motion_smoothing:
				velocity.x = lerp(velocity.x, direction3D.x * effective_speed, acceleration * delta)
				velocity.z = lerp(velocity.z, direction3D.z * effective_speed, acceleration * delta)
			else:
				velocity.x = direction3D.x * effective_speed
				velocity.z = direction3D.z * effective_speed
		else:
			# Only steer in mid-air if the player is actively pressing movement keys (preserves wall-jump momentum!)
			if input_dir != Vector2.ZERO:
				if motion_smoothing:
					velocity.x = lerp(velocity.x, direction3D.x * effective_speed, (acceleration * 0.5) * delta)
					velocity.z = lerp(velocity.z, direction3D.z * effective_speed, (acceleration * 0.5) * delta)
	else:
		if is_on_floor():
			if motion_smoothing:
				velocity.x = lerp(velocity.x, direction3D.x * effective_speed, acceleration * delta)
				velocity.z = lerp(velocity.z, direction3D.z * effective_speed, acceleration * delta)
			else:
				velocity.x = direction3D.x * effective_speed
				velocity.z = direction3D.z * effective_speed

func _handle_head_rotation(_delta : float) -> void:
	if invert_camera_x_axis: HEAD.rotation_degrees.y -= mouse_input.x * mouse_sensitivity * -1
	else: HEAD.rotation_degrees.y -= mouse_input.x * mouse_sensitivity

	if invert_camera_y_axis: HEAD.rotation_degrees.x -= mouse_input.y * mouse_sensitivity * -1
	else: HEAD.rotation_degrees.x -= mouse_input.y * mouse_sensitivity

	mouse_input = Vector2.ZERO
	HEAD.rotation_degrees.x = clamp(HEAD.rotation_degrees.x, -90, 90)

func _check_controls() -> void:
	if !InputMap.has_action(controls.JUMP): jumping_enabled = false
	if !InputMap.has_action(controls.FORWARD): immobile = true
	if !InputMap.has_action(controls.CROUCH): crouch_enabled = false
	if !InputMap.has_action(controls.SPRINT): sprint_enabled = false

func _handle_state(moving : bool) -> void:
	if sprint_enabled and state != "climbing" and state != "grappling":
		if Input.is_action_pressed(controls.SPRINT) and state != "crouching" and moving:
			if state != "sprinting": _enter_sprint_state()
		elif state == "sprinting": _enter_normal_state()

	if crouch_enabled and state != "climbing" and state != "grappling":
		if Input.is_action_pressed(controls.CROUCH) and state != "sprinting":
			if state != "crouching": _enter_crouch_state()
		elif state == "crouching" and !$CrouchCeilingDetection.is_colliding():
			_enter_normal_state()

func _enter_normal_state() -> void:
	state = "normal"
	speed = base_speed

func _enter_crouch_state() -> void:
	state = "crouching"
	speed = crouch_speed

func _enter_sprint_state() -> void:
	state = "sprinting"
	speed = sprint_speed
#endregion

#region Animations (Dynamic Headbob & Landing)
func _initialize_animations() -> void:
	HEADBOB_ANIMATION.play("RESET")
	JUMP_ANIMATION.play("RESET")
	CROUCH_ANIMATION.play("RESET")

func _play_headbob_animation(moving : bool) -> void:
	if state == "climbing":
		if current_speed > 0.1:
			HEADBOB_ANIMATION.play("walk", 0.25)
			HEADBOB_ANIMATION.speed_scale = (current_speed / base_speed) * 1.2
		else:
			HEADBOB_ANIMATION.play("RESET", 0.25)
	elif moving and is_on_floor():
		var use_headbob_animation : String
		match state:
			"normal","crouching": use_headbob_animation = "walk"
			"sprinting": use_headbob_animation = "sprint"

		var was_playing : bool = false
		if HEADBOB_ANIMATION.current_animation == use_headbob_animation:
			was_playing = true

		HEADBOB_ANIMATION.play(use_headbob_animation, 0.25)
		
		if state == "sprinting":
			HEADBOB_ANIMATION.speed_scale = (current_speed / base_speed) * 2.2
		else:
			HEADBOB_ANIMATION.speed_scale = (current_speed / base_speed) * 1.5
			
		if !was_playing:
			HEADBOB_ANIMATION.seek(float(randi() % 2))
	else:
		if HEADBOB_ANIMATION.current_animation == "sprint" or HEADBOB_ANIMATION.current_animation == "walk":
			HEADBOB_ANIMATION.speed_scale = 1
			HEADBOB_ANIMATION.play("RESET", 1)

func _play_jump_animation() -> void:
	if !was_on_floor and is_on_floor():
		var facing_direction : Vector3 = CAMERA.get_global_transform().basis.x
		var facing_direction_2D : Vector2 = Vector2(facing_direction.x, facing_direction.z).normalized()
		var velocity_2D : Vector2 = Vector2(velocity.x, velocity.z).normalized()
		var side_landed : int = round(velocity_2D.dot(facing_direction_2D))

		if side_landed > 0: JUMP_ANIMATION.play("land_right", 0.25)
		elif side_landed < 0: JUMP_ANIMATION.play("land_left", 0.25)
		else: JUMP_ANIMATION.play("land_center", 0.25)
#endregion

#region Debug Menu & Misc
func _update_debug_menu_per_frame() -> void:
	if !$UserInterface/DebugPanel.visible: return
	$UserInterface/DebugPanel.add_property("State", state, 4)

func _update_debug_menu_per_tick() -> void:
	if !$UserInterface/DebugPanel.visible: return
	$UserInterface/DebugPanel.add_property("Speed", snappedf(current_speed, 0.001), 1)

func _unhandled_input(event : InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.screen_relative

func change_reticle(reticle) -> void:
	if RETICLE: RETICLE.queue_free()
	RETICLE = load(reticle).instantiate()
	RETICLE.character = self
	$UserInterface.add_child(RETICLE)

func _update_camera_fov() -> void:
	if state == "sprinting": CAMERA.fov = lerp(CAMERA.fov, 85.0, 0.3)
	else: CAMERA.fov = lerp(CAMERA.fov, 75.0, 0.3)

func _handle_pausing() -> void:
	if Input.is_action_just_pressed(controls.PAUSE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
#endregion
