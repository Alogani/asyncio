import asyncsync
import ./exports/asynciobase {.all.}
import ./exports/asynciochilds


proc removeNils(streams: seq[AsyncIoBase]): seq[AsyncIoBase] =
    result = newSeqOfCap[AsyncIoBase](streams.len())
    for stream in streams:
        if stream != nil:
            result.add stream

proc buildReader*(chainReaders: seq[AsyncIoBase], closeEvent: Future[void] = nil,
        createCaptureStream = false, mustBeAFile = false): tuple[reader: AsyncIoBase, capture: AsyncIoBase] =
    ## Reading from return value is equivalent to reading from chainReaders argument
    ## If closeEvent is triggered, the built reader can reach EOF before chainReaders reach EOF.
    ## Providing closeEvent remove some optimizations to make it possible
    ## All input args and the return values should be closed manually by caller once done
    ## 
    ## Nil stream can be provided, they will be ignored
    let chainReaders = removeNils(chainReaders)
    if chainReaders.len() == 0:
        return (nil, nil)
    if chainReaders.len() == 1 and not createCaptureStream and closeEvent == nil:
        if (mustBeAFile and chainReaders[0] of AsyncFile) or not mustBeAFile:
            return (chainReaders[0], nil)
    let modifiedInput = (if chainReaders.len() == 1:
            chainReaders[0]
        else:
            AsyncChainReader.new(@chainReaders))
    if mustBeAFile:
        let output = AsyncPipe.new()
        if createCaptureStream:
            var captureStream = AsyncStream.new()
            AsyncTeeReader.new(modifiedInput, captureStream).transfer(
                output.reader, closeEvent).addCallback(proc() =
                    output.writer.close()
                    captureStream.writer.close()
                )
            return (output.reader, captureStream.reader)
        else:
            modifiedInput.transfer(output.writer, closeEvent).addCallback(proc() =
                output.writer.close()
            )
            return (output.reader, nil)
    else:
        if createCaptureStream:
            var captureStream = AsyncStream.new()
            var output = AsyncTeeReader.new(
                modifiedInput,
                captureStream,
                CloseWriter
            )
            if closeEvent != nil:
                closeEvent.addCallback(proc() =
                    output.close()
                )
            return (output, captureStream.reader)
        else:
            return (AsyncSoftCloser.new(modifiedInput), nil)

proc buildWriter*(writers: seq[AsyncIoBase], closeEvent: Future[void] = nil,
        createCaptureStream = false, mustBeAFile = false): tuple[reader: AsyncIoBase, capture: AsyncIoBase] =
    ## writing to return value is equivalent to reading from writers argument.
    ## Putting captureStream flag to true even if no writers are provided returns a legit value
    ## If closeEvent is triggered, the built writer can reach EOF before writers reach EOF.
    ## All other documentation from buildReader applies
    let writers = removeNils(writers)
    if writers.len() == 0 and not createCaptureStream:
        return (nil, nil)
    if writers.len() == 0 and createCaptureStream:
        if mustBeAFile:
            var output = AsyncPipe.new()
            return (output.writer, output.reader)
        else:
            var output = AsyncStream.new()
            return (output.writer, output.reader)
    if writers.len() == 1 and not createCaptureStream and closeEvent == nil:
        if (mustBeAFile and writers[0] of AsyncFile) or not mustBeAFile:
            return (writers[0], nil)
    var modifiedWriter = (if writers.len() == 1:
            writers[0]
        else:
            AsyncChainReader.new(@writers))
    if mustBeAFile:
        var output = AsyncPipe.new()
        if createCaptureStream:
            var captureStream = AsyncStream.new()
            var input = AsyncTeeWriter.new(modifiedWriter, captureStream.writer)
            output.transfer(input, closeEvent).addCallback(proc() =
                output.reader.close()
                captureStream.writer.close()
            )
            return (output.writer, captureStream.reader)
    else:
        if createCaptureStream:
            var captureStream = AsyncStream.new()
            var output = AsyncSoftCloser.new(AsyncTeeWriter.new(
                modifiedWriter,
                captureStream.writer,
            ))
            closeEvent.addCallback(proc() =
                output.close()
                captureStream.writer.close()
            )
            return (output, captureStream.reader)
        else:
            return (AsyncSoftCloser.new(modifiedWriter), nil)
    