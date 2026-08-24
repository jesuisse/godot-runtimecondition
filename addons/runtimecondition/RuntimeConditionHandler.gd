class_name MainConditionHandler extends Node

static var version: String = "v1.0.0"

static var description: String = "RuntimeCondition" + " " + version

## the root frame. It never goes out of scope because we keep this reference.
## Hence we can add default handlers for various Conditions to it.
var _root_frame: HandlerFrame

## this refers to the top frame in the chain of HandlerFrames. All frames in
## this chain are "active" and contain the "active" condition handlers
var _top_frame: WeakRef

func _init():
	# we should populate this with a catch-all handler that will deal with
	# unhandled errors by entering the debugger (in dev mode) or doing 
	# logging via push_error...
	_root_frame = HandlerFrame.new(self)
	_root_frame.add_handler(ConditionHandler.new(&'RuntimeCondition', _enter_debugger_handler))
	_set_top_frame(_root_frame)

## Raises a RuntimeCondition. 
## This starts condition handling from the point in the call stack where you
## raise the condition. 
func raise(condition: RuntimeCondition):
	var bt = Engine.capture_script_backtraces()
	condition.stacktrace = bt
	print(condition)
	print(bt)
	return _handle_condition(condition)


func _set_top_frame(frame: HandlerFrame):
	# It must be a weakref because otherwise the frame would not be destroyed
	# when its local variable goes out of scope
	_top_frame = weakref(frame)
	

func _recover_defined_state(args: Array, pos: int, size: int) -> int:
	while pos < size:
		if args[pos] is RuntimeCondition:
			return pos
		elif pos == size-1 and args[pos] is HandlerFrame:
			return pos
		pos += 1
	return pos

func _parse_bind_list(args: Array, frame: HandlerFrame):
	var l : int = args.size()
	var i : int = 0	
	while i < l:		
		if args[i] is StringName:
			if args[i+1] is Callable:
				handler(args[i], args[i+1])
				i += 2
			else:
				push_error("bind: Condition must be followed by Callable handler at argument %d" + str(i+1))
				i = _recover_defined_state(args, i+1, l)
		elif args[i] is HandlerFrame:
			if i == l-1:
				frame.include(args[i])
				i += 1
			else:
				push_error("bind: HandlerFrame must be the last argument if provided!")
				i = _recover_defined_state(args, i, l)
		else:
			push_error("bind: Syntax error; RuntimeCondition or HandlerFrame expected!")
			break

## binds condition handlers to specific conditions. the handlers become part of the set of
## active handlers.
func bind(...args) -> HandlerFrame:
	var frame : HandlerFrame = HandlerFrame.new(self)
	var parent : HandlerFrame = _top_frame.get_ref()
	if not parent:
		push_error("top frame no longer exists")
	frame._parent = parent
	_set_top_frame(frame)
	_parse_bind_list(args, frame)
	return frame


# Builds a new ConditionHandler object and register it as an active handler
func handler(condition, handler: Callable):
	var obj = ConditionHandler.new(condition, handler)
	var frame = _top_frame.get_ref()
	if frame:
		frame.add_handler(obj)
	else:
		push_error("frame no longer exists")


## Check the return value of the raise call and return from the function you're
## currently in if this returns true, with x as the return value, eg:
##   var e = raise(...)
##   if unhandled(e):
##      return e
## This is also used anywhere where you expect you might need to handle an 
## error, for example when getting a return value from a function that can
## produce conditions. Check what unhandled says about the return value and
## return if it's true:
##
## var retval = some_function(...)
## if unhandled(retval):
##      return retval
## This is the main way to unwind the stack to the place where we can actually
## handle a condition. unhandled will not only check whether x was not handled
## by the called function; it will also see if there are handlers registered 
## which can handle the error
func unhandled(x):
	if not x is RuntimeCondition or x.is_handled():
		return null
	else:
		# See if we can find a handler to deal with the condition
		return _handle_condition(x)


	

	
func _handle_condition(condition: RuntimeCondition):
	var handler = _find_handler_for(condition)
	return handler.call(condition)
	
func _find_handler_for(condition: RuntimeCondition):
	# TODO: Actually search for a matching handler. Currently we simply
	# give up.
	return _cannot_handle

# This is the fallthrough handler - it doesn't handle the condition, it just
# passes it on
func _cannot_handle(condition: RuntimeCondition):
	return condition

func _enter_debugger_handler(condition: RuntimeCondition):
	# this will enter the interactive debugger if we're running in 
	# the editor:
	if Engine.is_editor_hint():
		breakpoint



func _ready():
	print(description, " loaded.")
	
	var err = ErrorCondition.new("blah blah")
	if err.is_subclass_of(&"RuntimeCondition"):
		print("subclass")
	else:
		print("no subclass")
	
	

## A HandlerFrame contains a number of condition handlers; it is bound to a
## local variable in a function and will go out of scope when the function ends
## or another HandlerFrame is assigned to the variable. 
class HandlerFrame extends Resource:
	
	var _manager = null
	var _parent: HandlerFrame
	
	var _handlers : Array[ConditionHandler]

	## the return value of the last guard call
	var _guarded_retval

	var _unhandled : RuntimeCondition

	var unhandled: 
		get():
			return _unhandled

	var result:
		get():
			return _guarded_retval

	func _init(manager):
		_manager = manager

	func add_handler(handler: ConditionHandler):
		_handlers.append(handler)

	## This includes the handlers in the [param other] frame
	## in this frame.
	func include(other: HandlerFrame):
		for h in other._handlers:
			add_handler(h)

	func guard(retval):
		if retval is RuntimeCondition:
			if retval.is_handled():
				_guarded_retval = retval.return_value()
				_unhandled = null
			else:
				_guarded_retval = null
				_unhandled = retval
		else:
			_guarded_retval = retval
			_unhandled = null
	

	func _notification(what: int):
		if what == NOTIFICATION_PREDELETE:
			# we're going out of scope
			print("Frame is going out of scope")
			# Deregister our handlers
			#for key in _handlers:
			#	_manager._remove_handler(key)
			# this pops us from the top of the active
			# frames
			_manager._set_top_frame(_parent)
				
			

	
	
class ConditionHandler extends Resource:
	var condition: StringName
	var handler: Callable
	
	func _init(condition: StringName, handler: Callable):
		self.condition = condition
		self.handler = handler
	
	func _to_string() -> String:
		return "<ConditionHandler: "+str(self.condition)+">"
	

	

class ErrorCondition extends RuntimeCondition:
	
	var _is_handled: bool = false
	var _value
	
	static func clsname() -> StringName:
		return &'ErrorCondition'
	
	
	func _init(msg):
		self.msg = msg
		
	func _to_string() -> String:
		return "ErrorCondition: " + str(msg)

	func is_handled() -> bool:
		return _is_handled
	
	func value():
		return _value
		
