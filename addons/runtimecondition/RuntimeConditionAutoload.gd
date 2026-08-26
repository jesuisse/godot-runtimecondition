## (c) Copyright 2026-present by Pascal Schuppli. 
## see LICENSE file for licensing information.

## RuntimeCondition provides condition handling and a kind of "poor mans
## exception handling". Since GDScript does not support exceptions, if you
## want to use this addon, you need a fair amount of discipline to help
## get the desired stack unwinding behaviour manually.

## This is intended to be used as an Autoload, but works just fine as long as
## you add this node to your scene tree and keep a reference to it for 
## binding frames. See README.md for instructions on how to use it.

extends Node

const itertools = preload("res://addons/itertools/itertools.gd")

const version: String = "v1.0.0"
const description: String = "RuntimeCondition" + " " + version

## the root frame. It never goes out of scope because we keep this reference.
## Hence we can add default handlers for various Conditions to it.
var _root_frame: HandlerFrame

## this refers to the top frame in the chain of HandlerFrames. All frames in
## this chain are "active" and contain the "active" condition handlers. It must
## be a WeakRef because a direct reference would keep the top frame alive when
## the function it is created in terminates. Do NOT keep references to 
## HandlerFrames around anywhere!
var _top_frame: WeakRef

func _init():
	# we populate the root frame with a catch-all handler that will deal with
	# unhandled errors by entering the debugger (in dev mode) or doing 
	# logging via push_error...
	_root_frame = HandlerFrame.new(self)	
	_root_frame.add_handler(ConditionHandler.new(RuntimeCondition, _enter_debugger_handler))
	_set_top_frame(_root_frame)


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
		if args[i] is GDScript:
			if args[i+1] is Callable:
				_top_frame.get_ref().add_handler(ConditionHandler.new(args[i], args[i+1]))
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
			print(args[i], typeof(args[i]))
			push_error("bind: Syntax error; RuntimeCondition or HandlerFrame expected!")
			break

## This sets a failsafe handler that will be run if none of the bound handlers
## match the condition. 
## The handler takes a single argument (the condition) and returns either a 
## value or a condition. If the failsafe handler returns another condition 
## instead of a value, the condition will be considered 'unhandled' and logged
## as an error using push_error.
func set_failsave_handler(handler: Callable):
	# replace the default failsave handler
	_top_frame._handlers[0] = ConditionHandler.new(RuntimeCondition, handler)


## Binds condition handlers to specific conditions. the handlers become part of the set of
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

func get_top_frame() -> HandlerFrame:
	return _top_frame.get_ref()


func _enter_debugger_handler(condition: RuntimeCondition):
	if OS.is_debug_build() and OS.has_feature("editor"):
		# Hi, dear dev. If your editor has dropped you to this breakpoint
		# while running an app: This happens because you're running a debug 
		# build of Godot with an editor available and the piece of code in 
		# stack frame 3 has raised a condition for which no handler was bound.		
		# What you experience right now is the default catchall condition handler
		# of the 'runtimecondition' addon in action. This is not a bug, it is
		# intentional behaviour. You can bind another catchall handler using
		# `set_failsave_handler(...)` if you don't like this one :-)
		#
		# If you continue execution from here and all code is written correctly,
		# you should be dropped all the way back to the function where the first
		# condition was bound.
		breakpoint
	
	# this re-raises the condition, leading to a "unhandled condition" error
	return condition

func _ready():
	print(description, " loaded.")


## A HandlerFrame contains a number of condition handlers; it is bound to a
## local variable in a function and will go out of scope when the function ends
## or another HandlerFrame is assigned to the variable. 
class HandlerFrame extends Resource:
	
	var _manager = null
	var _parent: HandlerFrame
	
	## condition handlers which were bound in this frame (and whose return
	## value will be caught in this frame)
	var _handlers : Array[ConditionHandler]

	## Only needed as a workaround around a Godot Bug with PREDELETE running
	## after the self reference was already nulled.
	var _instance_id: int
	
	# This gets set if a condition was raised somewhere further down the call
	# stack which is now bubbling up to the right frame 
	var _active_condition: RuntimeCondition = null
		
	## Returns true if you need to terminate the function and return to your
	## caller as soon as possible (immediately)
	var unwind:
		get():
			return _must_unwind(_active_condition)

	# Constructor
	func _init(manager):
		_manager = manager
		_instance_id = get_instance_id() 

	# Desctructor
	func _notification(what: int):
		if what != NOTIFICATION_PREDELETE:
			return
	
		# we're the top frame and going out of scope, so we need a new top frame
		_manager._set_top_frame(_parent)
		
		if _active_condition:
			# not _must_unwind(..) check but we can't call _must_unwind due to self being null
			if _active_condition._target_frame_id == _instance_id:
				push_warning("A condition handler bound in frame %d was run for '%s' but it's return value wasn't caught. Did you forget to catch( )?" % [_instance_id, str(_active_condition)])
			else:
				# _hand_condition_to_parent(_active_condition), but we can't call it due to self being null
				assert(_parent, "No parent to hand off the active condition")
				_parent._active_condition = _active_condition


	func add_handler(handler: ConditionHandler):
		_handlers.append(handler)

	# Returns an iterator for handlers which can handle [param condition]. 
	# The returned iterator will yield ConditionHandlers.
	func get_handlers_for(condition: RuntimeCondition) -> itertools.Iterator:
		return itertools.filter(func (h): return h.can_handle(condition), itertools.array_rev(_handlers))
	
	## Raises a RuntimeCondition. 
	## This starts condition handling from the point in the call stack where you
	## raise the condition. 
	func raise(condition: RuntimeCondition):
		var bt = Engine.capture_script_backtraces()
		condition.stacktrace = bt
		return _handle_condition(condition)

	## You should wrap functions which can raise conditions in catch. 
	## [param value]] then represents their return value.
	## catch either returns value, if no condition was raised or no
	## handler was run to deal with the condition, or the return value of the
	## condition handler that was run to handle a raised condition. 
	func catch(value):
		if not _active_condition or _must_unwind(_active_condition):
			# nothing to catch or wrong frame
			return value
		
		var retval = _active_condition._handled_retval
		_active_condition = null
		# catch the value the error handler left us and return that instead of
		# the return value of the called function. 
		return retval

	func _must_unwind(x) -> bool:
		if not x is RuntimeCondition:
			return false
		
		if _instance_id == x._target_frame_id:
			return false
		
		return true

	func _hand_condition_to_parent(c: RuntimeCondition):
		if _parent:
			_parent._active_condition = c
		else:
			# we log the condition because there's nothing much else we can do
			# without a parent to hand the condition to
			push_error(str(c))

	# Finds a handler which can handle the condition by waking the chain
	# of HandlerFrames backwards. 	
	func _find_handlers_for(condition: RuntimeCondition) -> itertools.Iterator:
		# we start at our own frame, which is currently the top
		var frame = self
		var matching: itertools.Iterator = itertools.iter([])
				
		while frame:
			matching = itertools.chain(matching, itertools.map(func (x): return [x.handler, frame], frame.get_handlers_for(condition)))
			frame = frame._parent
		return matching	

	func _handle_condition(condition: RuntimeCondition):
		var handlers : itertools.Iterator = _find_handlers_for(condition)
		for h in handlers:
			var handler = h[0]
			var frame = h[1]
			condition._is_handled = true
			condition._target_frame_id = frame._instance_id
			var value = handler.call(condition)
			if value is RuntimeCondition:
				if value == condition:
					# handler returned the same condition, mark it as unhandled
					condition._is_handled = false
				else:
					# handler returned a new condition, so we must handle
					# this new condition instead
					_handle_condition(value)
					return
			
			if condition.is_handled():
				condition.set_handled_value(value)
				break
		
		if not condition.is_handled():
			# this happens if the failsave handler returns a condition or
			# if the failsave handler gets deleted (even though there's no
			# API method for deleting it...			
			push_error("Unhandled condition '%s'" % str(condition))
			condition._target_frame_id = _manager._root_frame._instance_id
			
		if _must_unwind(condition):
			_active_condition = condition
			_hand_condition_to_parent(condition)



class ConditionHandler extends Resource:
	var condition_class
	var handler: Callable
	
	func _init(condition, handler: Callable):
		self.condition_class = condition
		self.handler = handler
	
	func can_handle(condition: RuntimeCondition) -> bool:
		return is_instance_of(condition, condition_class)
	
	func _to_string() -> String:
		return "<ConditionHandler: "+str(self.condition_class)+">"


## This is the topmost Error. Extend this to define your own error classes.
class Error extends RuntimeCondition:
			
	func clsname() -> StringName:
		return &'Error'

	func _init(msg):
		self.msg = msg
		
	func _to_string() -> String:
		return str(clsname()) + ": " + str(msg)

## An example of a new error class (without any additional functionality)
class ValueError extends Error:	
	func clsname() -> StringName:
		return &'ValueError'
	
