import std/unittest
import asyncio, asyncio/[asynchainreader, asyncstring]

proc main() {.async.} =
    test "AsyncChainReader with asyncstring":
        var stream = AsyncChainReader.new(
            AsyncString.new("a", "b", "c"),
            AsyncString.new("d", "e", "f")
        )
        stream.closeWhenFlushed()
        check (await stream.readAll()) == "abcdef"
        check stream.isClosed

waitFor main()