extends Node2D

@onready var cond = $"/root/Condition"


func _ready():
	var E = cond.bind(cond.ValueError, something_wicked_happened)

	print("Entering _ready...")
	
	var result = E.catch(first_function())
	if E.unwind: return
	
	print("We're done with result ", result)
	print("Leaving _ready...")

func something_wicked_happened(condition: RuntimeCondition):
	print("Caught a ValueError in _ready -> return 'fixed'")
	return "fixed"
	

func this_wont_handle_anything(condition: RuntimeCondition):
	print("Oh. A condition was raised. I'm supposed to handle it.")
	print("I don't know if I can handle this. I better pass this off")
	print("to some other handler.")
	return condition

func fix_error(condition: RuntimeCondition):
	print(condition.msg)
	print(condition.stacktrace)
	print("Oh. A problem occured. I can fix it! The right solution is 22:")
	return 22
	
func first_function():
	# Note: The order matters! Matching conditions to handlers is done in
	# reverse order, so later entries match before earlier entries.
	var E = Condition.bind(		
		RuntimeCondition, this_wont_handle_anything, 
		) #cond.Error, fix_error)

	print("first_function entered...")

	var result = E.catch(second_function(22, 33))
	if E.unwind: return
	
	print("call to second_function returned ", result)
		
	# Also possible (THis will bind a handler just for the function call. The function call is always last):
	# result = F.guard(F.with(ErrorCondition, some_handler), 
	#                  second_function(22, 33))
	# if F.unwind(): return
	
	# If we need another set of condition handlers, we can simply bind another set
	# to F and the old object will be destroyed and deregister its handlers in the
	# process...
	# F = cond.bind(... another set of handlers ...)
	
	print("Leaving first_function...")
	return [result, 33]
		
	
func second_function(a: int, b: int):
	# new error frame
	var E = Condition.bind()
	
	print("second_function entered...")	
	
	var e = E.raise(cond.ValueError.new("A problem occured"))
	if E.unwind: return

	print("Leaving second_function...")
