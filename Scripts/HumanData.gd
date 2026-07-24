extends Resource
class_name HumanData

## Body proportions and team identity for a procedural humanoid.
## Change these numbers to generate different soldier silhouettes.

@export var height: float = 1.8
@export var shoulder_width: float = 0.44
@export var hip_width: float = 0.26
@export var leg_length: float = 0.95
@export var arm_length: float = 0.58
@export var head_radius: float = 0.15
@export var team_color: Color = Color(0.85, 0.15, 0.15)
@export var player_id: int = 1
@export var is_hunter: bool = false
