import std/unittest
import asyncio, asyncio/asyncstream

test "AsyncStream":
    var s = AsyncStream.new()
    var s2 = AsyncStream.new()
    discard waitFor s.write("data\n")
    check (waitFor s.readLine()) == "data"
    discard waitFor s2.write("data2\n")
    s2.close()
    check (waitFor s2.readAll()) == "data2\n"

    s = AsyncStream.new()
    s2 = AsyncStream.new()
    discard waitFor s.write("data\n")
    s.close()
    waitFor s.transfer(s2)
    s2.close()
    check (waitFor s2.readAll()) == "data\n"

    s = AsyncStream.new()
    s2 = AsyncStream.new()
    discard waitFor s.write("data")
    s.close()
    waitFor s.transfer(s2)
    s2.close()
    check (waitFor s2.readAll()) == "data"