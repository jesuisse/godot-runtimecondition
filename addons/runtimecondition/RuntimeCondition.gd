## RuntimeCondition is the base class for all runtime conditions you can
## raise.
@abstract class_name RuntimeCondition extends Resource

## short message / condition description
var msg : String

## Stack trace
var stacktrace

static func clsname() -> StringName:
	return &'RuntimeCondition'

## Returns true if this condition was handled and no longer needs attention.
@abstract func is_handled() -> bool
## Value (meaning differs - for handled conditions, this is 
## the return value)
@abstract func value()

@abstract func _to_string() -> String
