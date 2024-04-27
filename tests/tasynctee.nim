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
        check (await stream.readAll()) == "Hello"
        capture.closeWriter()
        check (await capture.readAll()) == "Hello"

    test "AsyncTeeWriter":
        var
            s1 = AsyncStream.new()
            s2 = AsyncStream.new()
            stream = AsyncTeeWriter.new(s1, s2)
        check (await stream.write("Hello")) > 0
        s1.closeWriter()
        s2.closeWriter()
        check (await s1.readAll()) == "Hello"
        check (await s2.readAll()) == "Hello"

    test "AsyncTeeWriter: close early":
        var
            s1 = AsyncStream.new()
            s2 = AsyncStream.new()
            stream = AsyncTeeWriter.new(s1, s2)
        s1.closeWriter()
        s2.closeWriter()
        check (await stream.write("Hello")) == 0
        check (await s1.readAll()) == ""
        check (await s2.readAll()) == ""

waitFor main()