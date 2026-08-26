## (c) Copyright 2026-present by Pascal Schuppli. 
## see LICENSE file for licensing information.

## RuntimeCondition is the base class for all runtime conditions you can
## raise.
##
## You can call decline() in your own condition handlers to notify the
## condition system that the handler has declined to handle it.
@abstract class_name RuntimeCondition extends Resource

## short message / condition description
var msg : String

## Stack trace (will be useless in production releases, so only rely on this
## in debugging OR enable stack traces for production releaes !)
var stacktrace

# If this is set, unwinding the stack continues until the given
# HandlerFrame is at the top of the frame stack.
var _target_frame
## Only needed as a workaround for a Godot Bug with PREDELETE notification
var _target_frame_id

var _is_handled : bool
var _handled_retval

## Override this in your derived Condition classes!
func clsname() -> StringName:
	return &'RuntimeCondition'

## Returns true if this condition was handled and no longer needs attention.
func is_handled() -> bool:
	return _is_handled

func set_handled_value(value):
	_handled_retval = value
	_is_handled = true

## Handlers can call this to decline handling this condition
func decline():
	_is_handled = false

@abstract func _to_string() -> String
