import std/unittest
import asyncio, asyncio/[asynchainreader, asyncstream]

proc main() {.async.} =
    test "AsyncChainReader with asyncstring":
        var stream = AsyncChainReader.new(
            AsyncString.new("a", "b", "c"),
            AsyncString.new("d", "e", "f")
        )
        check (await stream.readAll()) == "abcdef"
        check stream.isClosed

waitFor main()