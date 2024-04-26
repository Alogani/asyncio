import std/unittest
import asyncio, asyncio/[asynctee, asyncstream, asyncstring]

proc main() {.async.} =
    test "AsyncTeeReader":
        var
            capture = AsyncStream.new()
            stream = AsyncTeeReader.new(
                AsyncString.new("Hello"),
                capture
            )
        stream.closeWhenFlushed()
        check (await stream.readAll()) == "Hello"
        check (await capture.readAll()) == "Hello"

    test "AsyncTeeWriter":
        var
            s1 = AsyncStream.new()
            s2 = AsyncStream.new()
            stream = AsyncTeeWriter.new(s1, s2)
        check (await stream.write("Hello")) > 0
        stream.closeWhenFlushed()
        check (await s1.readAll()) == "Hello"
        check (await s2.readAll()) == "Hello"

    test "AsyncTeeWriter: close early":
        var
            s1 = AsyncStream.new()
            s2 = AsyncStream.new()
            stream = AsyncTeeWriter.new(s1, s2)
        stream.closeWhenFlushed()
        check (await stream.write("Hello")) == 0
        check (await s1.readAll()) == ""
        check (await s2.readAll()) == ""

waitFor main()