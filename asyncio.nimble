# Package

version       = "0.4.1"
author        = "alogani"
description   = "Async files and streams tools"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.2"
requires "asyncsync ~= 0.3.0"


task reinstall, "Reinstalls this package":
    exec("nimble remove " & projectName())
    exec("nimble install")

task genDocs, "Build the docs":
    ## importBuilder source code: https://github.com/Alogani/shellcmd-examples/blob/main/src/importbuilder.nim
    let bundlePath = "htmldocs/" & projectName() & ".nim"
    exec("./htmldocs/importbuilder --build src " & bundlePath & " --discardExports")
    exec("nim doc --project --index:on --outdir:htmldocs " & bundlePath)

task genDocsAndPush, "genDocs -> git push":
    genDocsTask()
    exec("git add htmldocs")
    exec("git commit -m 'Update docs'")
    exec("git push")