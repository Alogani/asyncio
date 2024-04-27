import std/unittest
import asyncio, asyncio/[asyncstream, asyncpipe]

proc pipeTester*[T: AsyncStream or AsyncPipe](name: string, OT: type T) =
    test name:
        var a = OT.new()
        var b = OT.new()
        discard waitFor a.write("data\n")
        check (waitFor a.readLine()) == "data"
        discard waitFor b.write("data2\n")
        b.closeWriter()
        check (waitFor b.readAll()) == "data2\n"

        a = OT.new()
        b = OT.new()
        discard waitFor a.write("data\n")
        a.closeWriter()
        waitFor a.transfer(b)
        b.closeWriter()
        check (waitFor b.readAll()) == "data\n"

        a = OT.new()
        b = OT.new()
        discard waitFor a.write("data")
        a.closeWriter()
        waitFor a.transfer(b)
        b.closeWriter()
        check (waitFor b.readAll()) == "data"