import ./exports/asynciobase {.all.}
import ./asyncstream

type
    AsyncString* = ref object of AsyncStream
    ## Immutable stream never blocking


proc new*(T: type AsyncString, data: varargs[string]): T


proc new*(T: type AsyncString, data: varargs[string]): T =
    result = cast[AsyncString](AsyncStream.new())
    for chunk in data:
        discard result.writeUnlocked(chunk, nil)
    result.close()
