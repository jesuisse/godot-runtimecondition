extends Node2D

@onready var cond = $"/root/RuntimeConditionHandler"


func _ready():
	var result = first_function()
	if cond.unhandled(result):
		push_error("Could not handle " + str(result))
	
	test(one(), two())

func test(a, b):
	print("in test")
	print(a, b)
			
func one():
	print("in one")
	return 1
func two():
	print("in two")
	return 2

func this_wont_handle_anything(condition: RuntimeCondition):
	print("Hmmm. Don't know if I can handle this. I better pass this on.")
	return condition

func fix_error(condition: RuntimeCondition):
	print("Oh. A problem occured. I can fix it! The right solution is 22")
	return 22
	
func first_function():
	# frame will go out of scope and we can use the PREDELETE notification
	# to make sure we unbind the handlers
	var H = cond.bind(
		&'ErrorCondition', fix_error,
		&'RuntimeCondition', this_wont_handle_anything)
	
	"""
	# The above is ok for simple functions where we only have one unhandled()
	# call or each one must be handled the same way. In case we have different
	# calls, we must localize the registered handlers. We might do that somewhat
	# like that: 
	var one_result = cond.with(
		cond.catch(cond.ErrorCondition, fix_error),
		cond.catch(RuntimeCondition, this_wont_handle_anything),
		second_function(44, 45))
	if cond.unhandled(one_result): return one_result
	"""
		
	var result = H.guard(second_function(22, 33)); if H.unhandled: return H.unhandled
	
	result = second_function(22, 23); if cond.unhandled(result): return result
	
	# Also possible, in order to allow for typed results:
	#H.guard(second_function(22, 33))
	#if H.unhandled: return H.unhandled
	#var result : float = H.result as float
	
	
	
	
	# If we need another set of condition handlers, we can simply bind another set
	# to F and the old object will be destroyed and deregister its handlers in the
	# process...
	# F = cond.bind(... another set of handlers ...)
	
		
	
func second_function(a: int, b: int):
	
	var e = cond.raise(cond.ErrorCondition.new("A problem occured"))
	if cond.unhandled(e): return e

		
		
	
	
	
	
	
