import std/unittest
import asyncio

import std/strutils

proc asyncTwoEndTester*[T: AsyncStream or AsyncPipe](name: string, OT: type T) =
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

proc main() {.async.} =
    suite "Asyncbuffer in normal mode":
        const bufSize = 100
        var
            unbufferedStream = AsyncStream.new()
            bufferedStream = AsyncBuffer.new(unbufferedStream, bufSize)

        test "isEmpty":
            check bufferedStream.bufLen() == (0, 0)

        test "Write less than buffer":
            discard await bufferedStream.write("A".repeat(50))
            check unbufferedStream.bufLen() == 0
            check bufferedStream.bufLen() == (0, 50)

        test "Write more than buffer":
            discard await bufferedStream.write("A".repeat(200))
            check unbufferedStream.bufLen() == 250
            check bufferedStream.bufLen() == (0, 0)

        test "Small read on empty buffer":
            check "A".repeat(10) == (await bufferedStream.read(10))
            check unbufferedStream.bufLen() == 150
            check bufferedStream.bufLen() == (bufSize - 10, 0)

        test "Small read on non empty buffer":
            check "A".repeat(10) == (await bufferedStream.read(10))
            check unbufferedStream.bufLen() == 150
            check bufferedStream.bufLen() == (bufSize - 10 * 2, 0)

        test "Read Chunk":
            check "A".repeat(bufSize - 10 * 2) == (await bufferedStream.readChunk())
            check unbufferedStream.bufLen() == 150
            check bufferedStream.bufLen() == (0, 0)

        test "Read all":
            discard await bufferedStream.write("A".repeat(200))
            unbufferedStream.writer.close()
            discard (await bufferedStream.read(10))
            check unbufferedStream.bufLen() == 250
            check bufferedStream.bufLen() == (90, 0)
            check "A".repeat(340) == (await bufferedStream.readAll())

    suite "Asyncbuffer in custom modes":
        const bufSize = 100
        var
            unbufferedStream = AsyncStream.new()
            bufferedStream = AsyncBuffer.new(unbufferedStream, bufSize)

        test "Passthrough Buffer: Write less than buffer":
            await bufferedStream.setBufferInPassthroughMode()
            discard await bufferedStream.write("A".repeat(50))
            check unbufferedStream.bufLen() == 50
            check bufferedStream.bufLen() == (0, 0)
        
        test "Passthrough Buffer: Small read buffer":
            check "A".repeat(10) == (await bufferedStream.read(10))
            check unbufferedStream.bufLen() == 40
            check bufferedStream.bufLen() == (0, 0)

        test "Restore in normal mode":
            bufferedStream.setBufferInNormalMode()
            discard await bufferedStream.fillBuffer(10)
            check unbufferedStream.bufLen() == 30
            check bufferedStream.bufLen() == (10, 0)

        test "Unbound Buffer: Read":
            bufferedStream.setBufferInUnboundMode()
            check "A".repeat(10) == (await bufferedStream.read(20))
            check unbufferedStream.bufLen() == 30
            check bufferedStream.bufLen() == (0, 0)

        test "Unbound Buffer: Write more than buffer":
            discard await bufferedStream.write("A".repeat(200))
            check unbufferedStream.bufLen() == 30
            check bufferedStream.bufLen() == (0, 200)

    suite "AsyncChainReader with asyncstring":
        var stream = AsyncChainReader.new(
            AsyncString.new("a", "b", "c"),
            AsyncString.new("d", "e", "f")
        )
        check (await stream.readAll()) == "abcdef"
        check stream.closed

    suite "AsyncPipe":
        asyncTwoEndTester("AsyncPipe", AsyncPipe)

    suite "AsyncStream":
        asyncTwoEndTester("AsyncStream", AsyncStream)

    suite "AsyncTeeReader":
        var
            capture = AsyncStream.new()
            stream = AsyncTeeReader.new(
                AsyncString.new("Hello"),
                capture
            )
        check (await stream.readAll()) == "Hello"
        capture.writer.close()
        check (await capture.readAll()) == "Hello"

    suite "AsyncTeeWriter":
        block:
            ## Close after
            var
                s1 = AsyncStream.new()
                s2 = AsyncStream.new()
                stream = AsyncTeeWriter.new(s1, s2)
            check (await stream.write("Hello")) > 0
            s1.writer.close()
            s2.writer.close()
            check (await s1.readAll()) == "Hello"
            check (await s2.readAll()) == "Hello"

        block:
            ## Close early
            var
                s1 = AsyncStream.new()
                s2 = AsyncStream.new()
                stream = AsyncTeeWriter.new(s1, s2)
            s1.writer.close()
            s2.writer.close()
            check (await stream.write("Hello")) == 0
            check (await s1.readAll()) == ""
            check (await s2.readAll()) == ""

waitFor main()