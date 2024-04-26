import std/unittest
import asyncio, asyncio/[asyncpipe]

import ./pipechecks

pipeTester("AsyncPipe", AsyncPipe)