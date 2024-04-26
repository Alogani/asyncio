import std/unittest
import asyncio

proc pipeTester*(name: string, T: type AsyncIoBase) =
    test name:
        var a = T.new()
        var b = T.new()
        discard waitFor a.write("data\n")
        check (waitFor a.readLine()) == "data"
        discard waitFor b.write("data2\n")
        b.closeWhenFlushed()
        check (waitFor b.readAll()) == "data2\n"

        a = T.new()
        b = T.new()
        discard waitFor a.write("data\n")
        a.closeWhenFlushed()
        waitFor a.transfer(b)
        b.closeWhenFlushed()
        check (waitFor b.readAll()) == "data\n"

        a = T.new()
        b = T.new()
        discard waitFor a.write("data")
        a.closeWhenFlushed()
        waitFor a.transfer(b)
        b.closeWhenFlushed()
        check (waitFor b.readAll()) == "data"