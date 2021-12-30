version       = "0.0.1"
author        = "Anuken"
description   = "none"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["nyj"]
binDir        = "build"

requires "nim >= 1.6.2"
requires "https://github.com/Anuken/fau#" & staticExec("git -C fau rev-parse HEAD")

import strformat, os

template shell(args: string) =
  try: exec(args)
  except OSError: quit(1)

const
  app = "nyj"

  builds = [
    #(name: "linux64", os: "linux", cpu: "amd64", args: ""), #doesn't work due to glibc
    (name: "win64", os: "windows", cpu: "amd64", args: "--gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-g++"),
  ]

task pack, "Pack textures":
  shell &"faupack -p:{getCurrentDir()}/assets-raw/sprites -o:{getCurrentDir()}/assets/atlas"

task debug, "Debug build":
  shell &"nim r -d:debug src/{app}"

task release, "Release build":
  shell &"nim r -d:release -d:danger -o:build/{app} src/{app}"

task web, "Deploy web build":
  mkDir "build/web"
  shell &"nim c -f -d:emscripten -d:danger src/{app}.nim"
  writeFile("build/web/index.html", readFile("build/web/index.html").replace("$title$", capitalizeAscii(app)))

task deploy, "Build for all platforms":
  webTask()

  for name, os, cpu, args in builds.items:
    let
      exeName = &"{app}-{name}"
      dir = "build"
      exeExt = if os == "windows": ".exe" else: ""
      bin = dir / exeName & exeExt

    mkDir dir
    shell &"nim --cpu:{cpu} --os:{os} --app:gui -f {args} -d:danger -o:{bin} c src/{app}"
    shell &"strip -s {bin}"
    #shell &"upx-ucl --best {bin}"

  cd "build"
  shell &"zip -9r {app}-web.zip web/*"

