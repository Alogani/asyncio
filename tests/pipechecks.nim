import std/unittest
import asyncio, asyncio/[asyncstream, asyncpipe]

proc pipeTester*[T: AsyncStream or AsyncPipe](name: string, OT: type T) =
    test name:
        var a = OT.new()
        var b = OT.new()
        discard waitFor a.write("data\n")
        check (waitFor a.readLine()) == "data"
        discard waitFor b.write("data2\n")
        b.writer.close()
        check (waitFor b.readAll()) == "data2\n"

        a = OT.new()
        b = OT.new()
        discard waitFor a.write("data\n")
        a.writer.close()
        waitFor a.transfer(b)
        b.writer.close()
        check (waitFor b.readAll()) == "data\n"

        a = OT.new()
        b = OT.new()
        discard waitFor a.write("data")
        a.writer.close()
        waitFor a.transfer(b)
        b.writer.close()
        check (waitFor b.readAll()) == "data"