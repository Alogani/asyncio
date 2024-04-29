# Asyncio

Asynchronous streams and files manipulation utilities in an object oriented manner

## Features

- Straightforward: as low level as possible, don't do anything fancy you didn't ask (all streams are unbuffered as default)
- Non blocking: any read/write operations can be cancelled using any future (like a timer)
- Efficient: no unecessary copies. readChunks methods used as default to speed up most operations (like transfer)
- high level made easy with transfer method, tee and chain objects

### Examples of objects defined :
- AsyncFile: to read and write to files (and much more on unix where almost anything is a file)
- AsyncPipe: to create and use unammed kernel fifo
- AsyncStream: to use an in-memorry fifo
- AsyncBuffer: to buffer any AsyncIo objects (can improve global speed for io that are fasters in larger chunks)
- AsyncTeeReader and AsyncTeeWriter: to easily duplicate one stream to multiple ones
- AsyncChainReader: to easily read from one stream after another
- StreamConverter: to use AsyncIo objects in proc where std/streams are expected (but will use waitFor under the hood)

## Getting started

### Installation

`nimble install asyncio`

### Usage (linux)

```
import asyncio

proc main() {.async.} =
  ## Write to stdout
  discard await stdoutAsync.write("Hello world")

  ## Flush all user input written to stdin
  await stdinAsync.clear()

  ## Read from stdin on a timer (Note: in linux, if stdin is a terminal, it is line buffered by the kernel)
  echo "DATA READ=", await stdinAsync.readAvailable(1024, sleepAsync(3000))

  ## Transfer all data from a file to another one (not performant) until EOF (enf of file) is reached
  await AsyncFile.new("myFile1").transfer(AsyncFile.new("myFile2"))

waitFor main()
```

### To go further

For common methods across all objects, please see [AsyncIoBase](https://github.com/Alogani/asyncio/blob/main/src/asyncio/exports/asynciobase.nim)

Please see tests folder or source code for specific usage of objects

## Before using it

- Unstable API : How you use asyncio is susceptible to change. It could occur to serve [asyncproc](https://github.com/Alogani/asyncproc) library development. If you want to use as a pre-release, please only install and use a tagged version and don't update frequently until v1.0.0 is reached. Releases with breaking change will make the second number of semver be updated (eg: v0.1.1 to v0.2.0). *_v1.0.0 is programmed to be released as soon as possible_*
- Only available in unix. Support for windows is not in the priority list
- Only support one async backend: std/asyncdispatch (incompatible with chronos)
- Not focused mainly on performance. Although development is focused to avoid unecessary or costly operations, asynchronous code has a large overhead and is usually far slower than sync one in many situations. Furthermore concisness and flexibilty are proritized
