RuntimeCondition
================

RuntimeCondition is a GDSCript library which aims to provide you with a flavour
of exception handling inspired by Common Lisp's condition system.

Since GDScript does not support exception handling and doesn't provide means
to unwind or otherwise control the stack, exception handling cannot be made
to work without the users (programmers) cooperation. This is what this addon 
tries to simplify.

# Differences to traditional exception handling

Traditional exceptions can be thrown/raised and will unwind the call stack up
to the place where a matching catch statement is present. They will also jump
over any code between the call which led to the raised exception and the 
exception handler.

RuntimeCondition cannot unwind the stack by itself, thus it requires the user
to cooperate. 

RuntimeCondition also doesn't run the exception handler *after* unwinding the
stack but *before*, meaning that the condition is handled at exactly the point
where it was raised. 

Exception handlers are functions of one argument (a condition) which can do
arbitrary work. If they return a condition (possibly the same that was passed
in to handle), the condition is considered 'unhandled' and the next matching
handler will be called for another attempt to handle the condition. If you
return another value (or null), this value will be returned by catch(..).

For this to work, you must bind condition handlers to the conditions which you
want to handle. You do this by creating a HandlerFrame object as a local 
variable in each function you want to participate in the condition handling.

# Implementation overview

Each function where you expect to throw or catch a condition, and each function
where such a condition might pass through on its travel along the call stack,
needs and exactly one HandlerFrame object. Each HandlerFrame object stores a 
list of bound handlers and a reference to the parent HandlerFrame. When a 
condition is raised, the HandlerFrames will be search from top to bottom and
in reverse order for a matching handler, the handler will be called and the 
stack will then be unwound until we reach the HandlerFrame where the handler
was bound.

![illustration](doc/call_frames.svg)
