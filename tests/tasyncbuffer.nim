import std/unittest
import asyncio, asyncio/asyncbuffer

import std/strutils


proc main() {.async.} =
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

    test "Write more than buffer"
        discard await bufferedStream.write("A".repeat(200))
        check unbufferedStream.bufLen() == 250
        check bufferedStream.bufLen() == (0, 0)

    test "Read on empty buffer"
        check "A".repeat(10) == (await bufferedStream.read(10))
        check unbufferedStream.bufLen() == 150
        check bufferedStream.bufLen() == (bufSize - 10, 0)

    test "Read on non empty buffer":
        check "A".repeat(10) == (await bufferedStream.read(10))
        check unbufferedStream.bufLen() == 150
        check bufferedStream.bufLen() == (bufSize - 10 * 2, 0)

    test "Read Chunk":
        check "A".repeat(bufSize - 10 * 2) == (await bufferedStream.readChunk())
        check unbufferedStream.bufLen() == 150
        check bufferedStream.bufLen() == (0, 0)

    test "Read all":
        discard await bufferedStream.write("A".repeat(200))
        unbufferedStream.close()
        discard (await bufferedStream.read(10))
        check unbufferedStream.bufLen() == 200
        check bufferedStream.bufLen() == (140, 0)
        check "A".repeat(340) == (await bufferedStream.readAll())


waitFor main()