# COPYRIGHT Colormatic Studios
# MIT license
# Updated with Full Procedural FPS Hand Animations (Sway, Fall/Land, Wrist Grapple Aim & Recoil, Climb, Pickup/Throw)

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

@export_subgroup("Hands & Grapple Visuals")
## Root Node3D of the imported hands.glb inside CAMERA
@export var HANDS_ROOT : Node3D
## Left hand MeshInstance3D
@export var LEFT_HAND_MESH : MeshInstance3D
## Right hand MeshInstance3D (with the wrist grapple launcher)
@export var RIGHT_HAND_MESH : MeshInstance3D
## Node3D placed at the tip of the wrist launcher where the rope starts
@export var GRAPPLE_MUZZLE : Node3D
## MeshInstance3D with a CylinderMesh (height 1.0) to render the grapple cable
@export var GRAPPLE_ROPE_MESH : MeshInstance3D
## The separated 3D hook model that sits on the wrist and flies to the wall when fired
@export var GRAPPLE_HOOK_TIP : Node3D
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
const GRAPPLE_COOLDOWN : float = 2.0
var hook_flight_progress : float = 0.0 # Animates the hook flying from wrist to wall
var hook_holstered_parent : Node3D = null
var hook_holstered_transform : Transform3D

# Climbing, Wall-Jump & Mantling Variables
var climb_timer : float = 0.0
var climb_cooldown_timer : float = 0.0
const MAX_CLIMB_TIME : float = 10.0
const CLIMB_COOLDOWN : float = 10.0
var last_wall_normal : Vector3 = Vector3.ZERO
var wall_jump_lock_timer : float = 0.0
var mantle_boost_timer : float = 0.0
var mantle_direction : Vector3 = Vector3.ZERO

# Procedural Hand Animation Variables
var climb_anim_cycle : float = 0.0
var walk_bob_cycle : float = 0.0
var hands_base_pos : Vector3 = Vector3.ZERO
var hands_base_rot : Vector3 = Vector3.ZERO
var left_hand_base_pos : Vector3 = Vector3.ZERO
var left_hand_base_rot : Vector3 = Vector3.ZERO
var right_hand_base_pos : Vector3 = Vector3.ZERO
var right_hand_base_rot : Vector3 = Vector3.ZERO
var current_fold_weight : float = 0.0
var current_fist_weight : float = 0.0
var hand_sway_offset : Vector2 = Vector2.ZERO
var hand_land_dip : float = 0.0
var hand_action_timer : float = 0.0
var hand_action_type : String = "" # "pickup", "throw", "grapple_fire"

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

	# Auto-detect HANDS_ROOT and hand meshes
	if not HANDS_ROOT and CAMERA and CAMERA.has_node("hands"):
		HANDS_ROOT = CAMERA.get_node("hands")
	if HANDS_ROOT:
		if not LEFT_HAND_MESH and HANDS_ROOT.has_node("Cube"):
			LEFT_HAND_MESH = HANDS_ROOT.get_node("Cube")
		if not RIGHT_HAND_MESH and HANDS_ROOT.has_node("Cube2"):
			RIGHT_HAND_MESH = HANDS_ROOT.get_node("Cube2")
		if HANDS_ROOT.has_node("Cube_002"):
			HANDS_ROOT.get_node("Cube_002").visible = false

	# Keep CULL_BACK on hands so backfaces don't fight with frontfaces (fixes weird lighting artifacts!)
	_enable_viewmodel_depth_overlay(LEFT_HAND_MESH, 1.0, false)
	_enable_viewmodel_depth_overlay(RIGHT_HAND_MESH, 1.0, false)

	# Save exact holstered transform of GrappleHookTip
	if GRAPPLE_HOOK_TIP:
		hook_holstered_parent = GRAPPLE_HOOK_TIP.get_parent()
		hook_holstered_transform = GRAPPLE_HOOK_TIP.transform
		_enable_viewmodel_depth_overlay(GRAPPLE_HOOK_TIP, 2.0, true)

	# Store initial transforms for procedural hand animations
	if HANDS_ROOT:
		hands_base_pos = HANDS_ROOT.position
		hands_base_rot = HANDS_ROOT.rotation_degrees
	if LEFT_HAND_MESH:
		left_hand_base_pos = LEFT_HAND_MESH.position
		left_hand_base_rot = LEFT_HAND_MESH.rotation_degrees
	if RIGHT_HAND_MESH:
		right_hand_base_pos = RIGHT_HAND_MESH.position
		right_hand_base_rot = RIGHT_HAND_MESH.rotation_degrees
	if GRAPPLE_ROPE_MESH:
		GRAPPLE_ROPE_MESH.visible = false
		GRAPPLE_ROPE_MESH.top_level = true

	_initialize_animations()
	_check_controls()
	_enter_normal_state()
	_update_inventory_ui()

func _enable_viewmodel_depth_overlay(target_node : Node3D, sort_order : float, disable_cull : bool) -> void:
	if not target_node: return
	var meshes : Array[MeshInstance3D] = []
	if target_node is MeshInstance3D:
		meshes.append(target_node)
	for child in target_node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child)
	for m in meshes:
		m.sorting_offset = sort_order
		var mat : Material = m.get_active_material(0)
		var unique_mat : BaseMaterial3D = mat.duplicate() if mat is BaseMaterial3D else StandardMaterial3D.new()
		unique_mat.no_depth_test = true
		unique_mat.cull_mode = BaseMaterial3D.CULL_DISABLED if disable_cull else BaseMaterial3D.CULL_BACK
		m.material_override = unique_mat

func _process(delta : float) -> void:
	if pausing_enabled:
		_handle_pausing()
	_update_debug_menu_per_frame()
	
	if grapple_timer > 0.0: grapple_timer -= delta
	if climb_cooldown_timer > 0.0: climb_cooldown_timer -= delta
	if wall_jump_lock_timer > 0.0: wall_jump_lock_timer -= delta
	if mantle_boost_timer > 0.0: mantle_boost_timer -= delta
	if hand_action_timer > 0.0: hand_action_timer -= delta
	
	# Update all procedural 3D hand animations, shape keys, and grapple visuals
	_update_hands_and_rope_animations(delta)

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
		if is_on_floor():
			if not was_on_floor:
				# Trigger downward hand impact when landing on the ground
				hand_land_dip = -0.18 if is_stomping else -0.09
			is_stomping = false
		else:
			_handle_air_stomp()

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

#region Full Procedural 3D Hands Animations, Shape Keys & Grapple Rope
func _update_hands_and_rope_animations(delta : float) -> void:
	# 1. Global Hand Bobbing, Mouse Sway, Air Inertia & Wall Orientation during Climbing
	hand_land_dip = lerpf(hand_land_dip, 0.0, 10.0 * delta)
	hand_sway_offset = hand_sway_offset.lerp(Vector2.ZERO, 10.0 * delta)
	
	if HANDS_ROOT:
		if state == "climbing":
			# Keep hands parallel to the wall surface regardless of where the camera looks up/down!
			var wall_into_dir : Vector3 = -last_wall_normal
			wall_into_dir.y = 0.0
			if wall_into_dir.length_squared() < 0.001:
				wall_into_dir = -HEAD.global_transform.basis.z
				wall_into_dir.y = 0.0
			wall_into_dir = wall_into_dir.normalized()
			
			# Position hands right in front of the player's chest facing the wall
			var target_world_pos : Vector3 = HEAD.global_position + Vector3(0.0, -0.22, 0.0) + (wall_into_dir * 0.42)
			var target_yaw : float = atan2(-wall_into_dir.x, -wall_into_dir.z)
			var target_world_rot : Vector3 = Vector3(0.0, rad_to_deg(target_yaw), 0.0)
			
			HANDS_ROOT.global_position = HANDS_ROOT.global_position.lerp(target_world_pos, 16.0 * delta)
			HANDS_ROOT.global_rotation_degrees = HANDS_ROOT.global_rotation_degrees.lerp(target_world_rot, 16.0 * delta)
		else:
			# Normal FPS mode: return smoothly to local camera-following transform
			var root_target_pos : Vector3 = hands_base_pos
			var root_target_rot : Vector3 = hands_base_rot
			
			var wall_pullback : float = 0.0
			if WALL_CHECK and WALL_CHECK.is_colliding():
				var wall_dist : float = WALL_CHECK.global_position.distance_to(WALL_CHECK.get_collision_point())
				if wall_dist < 1.15:
					wall_pullback = clamp((1.15 - wall_dist) * 0.45, 0.0, 0.38)
			root_target_pos.z += wall_pullback
			
			if is_on_floor() and moving and state != "grappling":
				var bob_freq : float = 14.0 if state == "sprinting" else 9.0
				var bob_amp : float = 0.045 if state == "sprinting" else 0.022
				walk_bob_cycle += delta * bob_freq
				root_target_pos.x += cos(walk_bob_cycle * 0.5) * bob_amp
				root_target_pos.y += abs(sin(walk_bob_cycle)) * bob_amp
				root_target_rot.z += cos(walk_bob_cycle * 0.5) * (4.0 if state == "sprinting" else 2.0)
				if state == "sprinting":
					root_target_rot.x -= 12.0
			else:
				walk_bob_cycle = 0.0
				
			if not is_on_floor() and state != "grappling":
				var air_offset_y : float = clamp(-velocity.y * 0.012, -0.08, 0.14)
				root_target_pos.y += air_offset_y
				root_target_rot.x += clamp(velocity.y * 1.8, -18.0, 18.0)
				
			root_target_pos.y += hand_land_dip
			root_target_pos.x += hand_sway_offset.x
			root_target_pos.y += hand_sway_offset.y
			root_target_rot.y += hand_sway_offset.x * 120.0
			
			HANDS_ROOT.position = HANDS_ROOT.position.lerp(root_target_pos, 16.0 * delta)
			HANDS_ROOT.rotation_degrees = HANDS_ROOT.rotation_degrees.lerp(root_target_rot, 16.0 * delta)

	# 2. Separate Shape Keys per Hand ("Normal", "Hold", and "fist")
	var left_target_hold : float = 0.0
	var left_target_fist : float = 0.0
	var right_target_hold : float = 0.0
	var right_target_fist : float = 0.0
	
	if is_grapple_attached or is_being_pulled:
		# Right hand in "fist" firing grapple; Left hand in "Hold" bracing on top of right arm!
		right_target_fist = 1.0
		left_target_hold = 1.0
	elif is_stomping:
		left_target_fist = 1.0
		right_target_fist = 1.0
	elif state == "climbing":
		left_target_hold = 1.0
		right_target_hold = 1.0
	elif carried_item != null:
		left_target_hold = 0.75
		right_target_hold = 0.75
	elif hand_action_timer > 0.0 and hand_action_type == "pickup":
		left_target_hold = 0.9
		right_target_hold = 0.9
	elif state == "sprinting":
		left_target_fist = 0.65
		right_target_fist = 0.65
		
	current_fold_weight = lerpf(current_fold_weight, left_target_hold, 14.0 * delta)
	current_fist_weight = lerpf(current_fist_weight, right_target_fist, 14.0 * delta)
	
	var right_hold_smooth : float = lerpf(0.0, right_target_hold, 1.0) if (is_grapple_attached or is_being_pulled) else current_fold_weight
	var left_fist_smooth : float = 0.0 if (is_grapple_attached or is_being_pulled) else current_fist_weight
	
	_apply_shape_keys_to_mesh(LEFT_HAND_MESH, 0.0, current_fold_weight, left_fist_smooth)
	_apply_shape_keys_to_mesh(RIGHT_HAND_MESH, 0.0, right_hold_smooth, current_fist_weight)
	
	# 3. Individual Left & Right Hand Action Animations
	var left_target_pos : Vector3 = left_hand_base_pos
	var left_target_rot : Vector3 = left_hand_base_rot
	var right_target_pos : Vector3 = right_hand_base_pos
	var right_target_rot : Vector3 = right_hand_base_rot

	# A) CLIMBING: Hands flat/parallel to the wall, alternating vertical pulls as you climb
	if state == "climbing":
		var climb_move_factor : float = 1.0 if current_speed > 0.1 else 0.0
		climb_anim_cycle += delta * (current_speed * 4.2 + 1.5) * climb_move_factor
		
		# Tilt palms forward so hands lie flat parallel to the vertical wall
		left_target_pos += Vector3(0.0, sin(climb_anim_cycle) * 0.16, -0.05 + cos(climb_anim_cycle) * 0.03)
		left_target_rot += Vector3(65.0 + sin(climb_anim_cycle) * 10.0, 0.0, 0.0)
		
		right_target_pos += Vector3(0.0, -sin(climb_anim_cycle) * 0.16, -0.05 - cos(climb_anim_cycle) * 0.03)
		right_target_rot += Vector3(65.0 - sin(climb_anim_cycle) * 10.0, 0.0, 0.0)

	# B) GRAPPLE AIM & BRACE: Right arm aims wrist launcher; Left hand (Hold) braces right on top of right forearm
	elif is_grapple_attached or is_being_pulled:
		var recoil_kick : float = (hand_action_timer / 0.25) if (hand_action_type == "grapple_fire" and hand_action_timer > 0.0) else 0.0
		var pull_shake : float = sin(Time.get_ticks_msec() * 0.04) * 0.015 if is_being_pulled else 0.0
		
		# Right hand points forward/downward with fist closed
		right_target_pos += Vector3(-0.06, 0.05 + pull_shake, -0.15 + (recoil_kick * 0.12))
		right_target_rot += Vector3(-55.0 + (recoil_kick * 25.0), 0.0, 0.0)
		
		# Left hand resting right on top of the right wrist/brace
		left_target_pos += Vector3(1.02, -0.02 + pull_shake, 0.74 + (recoil_kick * 0.10))
		left_target_rot += Vector3(-52.0 + (recoil_kick * 20.0), -48.0, -35.0)

	# C) PICKUP / THROW / CARRYING ITEM
	elif hand_action_timer > 0.0 and (hand_action_type == "pickup" or hand_action_type == "throw"):
		var reach_amt : float = sin((hand_action_timer / 0.25) * PI)
		var forward_push : float = -0.20 if hand_action_type == "throw" else -0.14
		var pitch_angle : float = -35.0 if hand_action_type == "throw" else 25.0
		
		left_target_pos += Vector3(0.05 * reach_amt, -0.04 * reach_amt, forward_push * reach_amt)
		right_target_pos += Vector3(-0.05 * reach_amt, -0.04 * reach_amt, forward_push * reach_amt)
		left_target_rot += Vector3(pitch_angle * reach_amt, 0.0, 0.0)
		right_target_rot += Vector3(pitch_angle * reach_amt, 0.0, 0.0)
	elif carried_item != null:
		left_target_pos += Vector3(0.06, -0.07, -0.08)
		right_target_pos += Vector3(-0.06, -0.07, -0.08)
		left_target_rot += Vector3(20.0, -15.0, 0.0)
		right_target_rot += Vector3(20.0, 15.0, 0.0)

	if LEFT_HAND_MESH:
		LEFT_HAND_MESH.position = LEFT_HAND_MESH.position.lerp(left_target_pos, 15.0 * delta)
		LEFT_HAND_MESH.rotation_degrees = LEFT_HAND_MESH.rotation_degrees.lerp(left_target_rot, 15.0 * delta)
	if RIGHT_HAND_MESH:
		RIGHT_HAND_MESH.position = RIGHT_HAND_MESH.position.lerp(right_target_pos, 15.0 * delta)
		RIGHT_HAND_MESH.rotation_degrees = RIGHT_HAND_MESH.rotation_degrees.lerp(right_target_rot, 15.0 * delta)

	# 4. Update 3D Grapple Rope and Flying/Retracting Hook Tip
	var muzzle_pos : Vector3 = GRAPPLE_MUZZLE.global_position if GRAPPLE_MUZZLE else (RIGHT_HAND_MESH.global_position if RIGHT_HAND_MESH else CAMERA.global_position)
	
	if is_grapple_attached:
		hook_flight_progress = move_toward(hook_flight_progress, 1.0, delta * 9.5)
	else:
		hook_flight_progress = move_toward(hook_flight_progress, 0.0, delta * 12.0)
		
	if hook_flight_progress > 0.001:
		var current_hook_pos : Vector3 = muzzle_pos.lerp(grapple_point, hook_flight_progress)
		var dist : float = muzzle_pos.distance_to(current_hook_pos)
		
		if GRAPPLE_HOOK_TIP:
			GRAPPLE_HOOK_TIP.top_level = true
			GRAPPLE_HOOK_TIP.visible = true
			if GRAPPLE_HOOK_TIP is MeshInstance3D and GRAPPLE_HOOK_TIP.material_override is BaseMaterial3D:
				GRAPPLE_HOOK_TIP.material_override.no_depth_test = false
			
			var world_scale : Vector3 = HANDS_ROOT.global_transform.basis.get_scale() if HANDS_ROOT else Vector3.ONE
			GRAPPLE_HOOK_TIP.scale = Vector3(abs(world_scale.x), abs(world_scale.y), abs(world_scale.z))
			GRAPPLE_HOOK_TIP.global_position = current_hook_pos
			if muzzle_pos.distance_to(grapple_point) > 0.05:
				GRAPPLE_HOOK_TIP.look_at(grapple_point, Vector3.UP)
		
		if GRAPPLE_ROPE_MESH and dist > 0.05:
			GRAPPLE_ROPE_MESH.visible = true
			GRAPPLE_ROPE_MESH.global_position = (muzzle_pos + current_hook_pos) * 0.5
			GRAPPLE_ROPE_MESH.look_at(current_hook_pos, Vector3.UP)
			GRAPPLE_ROPE_MESH.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			GRAPPLE_ROPE_MESH.scale = Vector3(1.0, dist, 1.0)
		elif GRAPPLE_ROPE_MESH:
			GRAPPLE_ROPE_MESH.visible = false
	else:
		if GRAPPLE_ROPE_MESH:
			GRAPPLE_ROPE_MESH.visible = false
		if GRAPPLE_HOOK_TIP:
			GRAPPLE_HOOK_TIP.top_level = false
			GRAPPLE_HOOK_TIP.transform = hook_holstered_transform
			GRAPPLE_HOOK_TIP.visible = true
			if GRAPPLE_HOOK_TIP is MeshInstance3D and GRAPPLE_HOOK_TIP.material_override is BaseMaterial3D:
				GRAPPLE_HOOK_TIP.material_override.no_depth_test = true

func _apply_shape_keys_to_mesh(mesh_inst : Node3D, normal_val : float, hold_val : float, fist_val : float) -> void:
	if not mesh_inst: return
	
	var meshes_to_update : Array[MeshInstance3D] = []
	if mesh_inst is MeshInstance3D:
		meshes_to_update.append(mesh_inst)
	for child in mesh_inst.find_children("*", "MeshInstance3D", true, false):
		meshes_to_update.append(child)
		
	for m in meshes_to_update:
		if not m.mesh: continue
		for i in range(m.get_blend_shape_count()):
			var bs_name : String = m.mesh.get_blend_shape_name(i).to_lower()
			if bs_name == "normal":
				m.set_blend_shape_value(i, normal_val)
			elif bs_name == "hold" or bs_name == "fold":
				m.set_blend_shape_value(i, hold_val)
			elif bs_name == "fist":
				m.set_blend_shape_value(i, fist_val)
#endregion

#region Sonic Air Stomp Logic (Press Ctrl in mid-air)
func _handle_air_stomp() -> void:
	var ctrl_down : bool = Input.is_key_pressed(KEY_CTRL)
	var stomp_just_pressed : bool = (ctrl_down and not was_Ctrl_pressed)
	was_Ctrl_pressed = ctrl_down
	
	if InputMap.has_action(controls.STOMP) and Input.is_action_just_pressed(controls.STOMP):
		stomp_just_pressed = true

	if stomp_just_pressed and not is_on_floor() and not is_stomping:
		is_stomping = true
		mantle_boost_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = -stomp_velocity
#endregion

#region Single-Slot Inventory & Weight System
func _handle_inventory_logic() -> void:
	if InputMap.has_action(controls.INTERACT) and Input.is_action_just_pressed(controls.INTERACT):
		if carried_item == null:
			_try_pickup_item()
		else:
			_release_item(drop_force, "pickup")

	if InputMap.has_action(controls.THROW) and Input.is_action_just_pressed(controls.THROW):
		if carried_item != null:
			_release_item(throw_force * weight_throw_mult, "throw")

func _try_pickup_item() -> void:
	if INTERACT_CHECK and INTERACT_CHECK.is_colliding():
		var collider = INTERACT_CHECK.get_collider()
		if collider is RigidBody3D and collider.is_in_group("pickup"):
			carried_item = collider
			carried_item.freeze = true
			carried_item.visible = false
			for child in carried_item.get_children():
				if child is CollisionShape3D:
					child.disabled = true
			
			hand_action_type = "pickup"
			hand_action_timer = 0.25
			_apply_item_weight(carried_item.mass)
			_update_inventory_ui()

func _release_item(impulse_strength : float, anim_type : String = "throw") -> void:
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
	
	var throw_vector : Vector3 = (forward_dir + Vector3(0, 0.15, 0)).normalized() * (impulse_strength * carried_item.mass)
	carried_item.apply_central_impulse(throw_vector + (velocity * 0.3 * carried_item.mass))
	
	hand_action_type = anim_type
	hand_action_timer = 0.25
	carried_item = null
	_reset_weight_modifiers()
	_update_inventory_ui()

func _apply_item_weight(item_mass : float) -> void:
	if item_mass <= medium_mass_threshold:
		weight_speed_mult = 1.0
		weight_jump_mult = 1.0
		weight_gravity_mult = 1.0
		weight_throw_mult = 1.0
		current_weight_label = "Leve"
	elif item_mass <= heavy_mass_threshold:
		weight_speed_mult = 0.85
		weight_jump_mult = 0.90
		weight_gravity_mult = 1.15
		weight_throw_mult = 0.80
		current_weight_label = "Médio"
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
				hook_flight_progress = 0.0
				hand_action_type = "grapple_fire"
				hand_action_timer = 0.25 # Triggers wrist aiming recoil kick
		
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

	if wall_jump_lock_timer > 0.0:
		return

	var is_holding_left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	if is_holding_left and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if WALL_CHECK and WALL_CHECK.is_colliding():
			var collider = WALL_CHECK.get_collider()
			var material_name = collider.name if collider else ""
			var hit_normal : Vector3 = WALL_CHECK.get_collision_normal()
			
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
					climb_timer += delta * weight_gravity_mult
					if climb_timer >= MAX_CLIMB_TIME:
						climb_cooldown_timer = CLIMB_COOLDOWN
						_enter_normal_state()
						return
				
				if Input.is_action_just_pressed(controls.JUMP):
					wall_jump_lock_timer = 0.35
					var jump_dir : Vector3 = (last_wall_normal * 1.15 + Vector3.UP * 1.35).normalized()
					velocity = jump_dir * (jump_velocity * weight_jump_mult) * 1.65
					hand_land_dip = -0.08
					if jump_animation:
						JUMP_ANIMATION.play("jump", 0.25)
					_enter_normal_state()
					return
		elif state == "climbing":
			var raw_input = Input.get_vector(controls.LEFT, controls.RIGHT, controls.FORWARD, controls.BACKWARD)
			if raw_input.y <= 0.1:
				_trigger_ledge_mantle()
			else:
				_enter_normal_state()
	else:
		if state == "climbing":
			_enter_normal_state()

func _trigger_ledge_mantle() -> void:
	var into_ledge_dir : Vector3 = -last_wall_normal
	into_ledge_dir.y = 0.0
	if into_ledge_dir.length_squared() < 0.01:
		into_ledge_dir = -HEAD.global_transform.basis.z
		into_ledge_dir.y = 0.0
	into_ledge_dir = into_ledge_dir.normalized()
	
	mantle_direction = into_ledge_dir
	mantle_boost_timer = 0.28
	wall_jump_lock_timer = 0.35
	hand_land_dip = -0.12
	
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
	
	var wall_suction : Vector3 = -normal * 1.5
	var climb_vel : Vector3 = (vertical_dir + lateral_dir).normalized() * (3.5 * weight_speed_mult)
	velocity = climb_vel + wall_suction
	move_and_slide()
	
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
				hand_land_dip = -0.07
				velocity.y += effective_jump
		else:
			if Input.is_action_just_pressed(controls.JUMP) and is_on_floor() and !low_ceiling:
				if jump_animation: JUMP_ANIMATION.play("jump", 0.25)
				hand_land_dip = -0.07
				velocity.y += effective_jump

func _handle_movement(delta : float, input_dir : Vector2) -> void:
	var direction2D := input_dir.rotated(-HEAD.rotation.y)
	var direction3D := Vector3(direction2D.x, 0, direction2D.y)
	var effective_speed : float = speed * weight_speed_mult
	
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

	# Accumulate mouse sway for the 3D FPS hands
	hand_sway_offset.x = clamp(hand_sway_offset.x - mouse_input.x * 0.0006, -0.05, 0.05)
	hand_sway_offset.y = clamp(hand_sway_offset.y + mouse_input.y * 0.0006, -0.05, 0.05)

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
