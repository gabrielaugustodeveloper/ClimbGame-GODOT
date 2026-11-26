extends Area3D

@export var respawn_point : Marker3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and respawn_point:
		body.global_position = respawn_point.global_position
		body.velocity = Vector3.ZERO
