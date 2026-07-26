class_name GOAPPlanner2D
extends RefCounted
## GOAPPlanner2D.gd — Goal-Oriented Action Planner & Utility AI Engine for CharOfLead.
## Inspired by F.E.A.R., Halo, and The Last of Us.

enum GoalType { ELIMINATE_TARGET, GAIN_LOS, FLANK_POSITION, UNSTICK }
enum ActionType { FOLLOW_PATH, LEAP_SURFACE, ATTACK, UNSTICK_VAULT }

static func evaluate_best_goal(beliefs: Dictionary) -> int:
	if bool(beliefs.get("stuck", false)):
		return GoalType.UNSTICK
	
	if bool(beliefs.get("has_los", false)):
		return GoalType.ELIMINATE_TARGET

	return GoalType.GAIN_LOS


static func plan_action_sequence(goal: int, beliefs: Dictionary) -> Array[int]:
	var plan: Array[int] = []

	match goal:
		GoalType.UNSTICK:
			plan.append(ActionType.UNSTICK_VAULT)
		
		GoalType.ELIMINATE_TARGET:
			if bool(beliefs.get("is_on_wall", false)) or bool(beliefs.get("is_on_ceiling", false)):
				plan.append(ActionType.LEAP_SURFACE)
			plan.append(ActionType.ATTACK)

		GoalType.GAIN_LOS, GoalType.FLANK_POSITION:
			if bool(beliefs.get("is_on_wall", false)) or bool(beliefs.get("is_on_ceiling", false)):
				plan.append(ActionType.LEAP_SURFACE)
			plan.append(ActionType.FOLLOW_PATH)
			plan.append(ActionType.ATTACK)

	return plan
