import ./exports/asynciobase {.all.}
import ./asyncstream

type
    AsyncString* = ref object of AsyncStream
        ## Immutable async stream/buffer, that can only be written at instantiation and closed when read


proc new*(T: type AsyncString, data: varargs[string]): T


proc new*(T: type AsyncString, data: varargs[string]): T =
    result = cast[AsyncString](AsyncStream.new())
    for chunk in data:
        discard result.writeUnlocked(chunk, nil)
    result.writer.close()
