class_name MainConditionHandler extends Node

static var version: String = "v1.0.0"

static var description: String = "RuntimeCondition" + " " + version

## this refers to the top frame in the chain of HandlerFrames. All frames in
## this chain are "active" and contain the "active" condition handlers
var _top_frame: WeakRef

# Free slots
var _free_handlers: Array[int] = []

# This contains the currently active handlers. 
var _active_handlers: Array[ConditionHandler] = []

## Raises a RuntimeCondition. 
## This starts condition handling from the point in the call stack where you
## raise the condition. 
func raise(condition: RuntimeCondition):
	var bt = Engine.capture_script_backtraces()
	condition.stacktrace = bt
	print(condition)
	print(bt)
	return _handle_condition(condition)


func _replace_top_with(frame: HandlerFrame):
	# It must be a weakref because otherwise the frame would not be destroyed
	# when its local variable goes out of scope
	_top_frame = WeakRef(frame)
	

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
				var hid: int = handler(args[i], args[i+1])
				frame.add_handler(hid, _get_handler_by_id(hid))
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
	_parse_bind_list(args, frame)
	return frame

func _set_handler(handler: ConditionHandler) -> int:
	# currently this code won't work because we'll add handlers out of order and this means
	# the handlers won't be found in the right order. We have to fix this...!
	var hid = -1
	if _free_handlers.size() > 0:
		hid = _free_handlers.pop_back()
		_active_handlers[hid] = handler
	else:
		hid = _active_handlers.size()
		_active_handlers.append(handler)
	return hid
	

func _get_handler_by_id(id: int) -> ConditionHandler:
	return _active_handlers[id]

func _remove_handler(hid):
	_active_handlers[hid] = null
	_free_handlers.append(hid)



# Builds a new ConditionHandler object and register it as an active handler
func handler(condition, handler: Callable) -> int:
	var obj = ConditionHandler.new(condition, handler)
	var hid = _set_handler(obj)
	return hid
		



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


func _ready():
	print(description, " loaded.")

## A HandlerFrame contains a number of condition handlers; it is bound to a
## local variable in a function and will go out of scope when the function ends
## or another HandlerFrame is assigned to the variable. It's main purpose is to 
## deregister its handlers when this happens.
class HandlerFrame extends Resource:
	
	var _manager = null
	var _parent: HandlerFrame
	
	var _handlers : Dictionary[int,ConditionHandler]

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

	func add_handler(hid: int, handler: ConditionHandler):
		_handlers[hid] = handler

	## This includes the handlers in the [param other] frame
	## in this frame.
	func include(other: HandlerFrame):
		for key in other._handlers:
			add_handler(key, other._handler[key])

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
			for key in _handlers:
				_manager._remove_handler(key)
			# this pops us from the top of the active
			# frames
			_manager._replace_top_frame_with(_parent)
				
			

	
	
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
		
