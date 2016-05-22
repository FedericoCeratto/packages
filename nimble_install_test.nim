#
# Nimble install test
#
# Copyright 2016 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see /usr/share/common-licenses/GPL-3
#

from algorithm import sortedByIt
import json
import os
import osproc
import strutils
import streams
import sequtils
import times

const
  nimble_binpath = "./nimble"
  timeout = 60

type
  Pkg = tuple[name, url: string]
  TestResult* {.pure.} = enum
    OK, FAIL, TIMEOUT
  InstRep* = tuple[title, url: string, test_result: TestResult]

include "install_test_report.tmpl"
include "install_test_output.tmpl"

proc gmtime(): string =
  return $getGmTime(getTime())

proc load_packages(): seq[Pkg] =
  result = @[]
  let pkg_list = parseJson(readFile("packages.json"))
  for pdata in pkg_list:
    result.add((pdata["name"].getStr(), pdata["web"].getStr()))
  result = result.sortedByIt(it[0])

proc write_output(p: Process, pkg: Pkg) =
  discard p.waitForExit()
  let output = p.outputStream().readAll()
  let page = generate_install_report_output_page(pkg.name, output, gmtime())
  writeFile("nimble_install_output_$#.html" % pkg.name, page)

proc main() =

  let packages = load_packages()
  var installation_reports: seq[InstRep] = @[]

  for pkg in packages:
    let
      tmp_dir = "/tmp/nimble_install_test/" / pkg.name
      cmd = "$# install $# --nimbleDir=$# -y" % [$nimble_binpath, $pkg.name, tmp_dir]
    createDir(tmp_dir)
    echo "Processing ", $pkg.name
    let
      p = startProcess(
        nimble_binpath,
        args=["install", $pkg.name, "--nimbleDir=$#" % tmp_dir, "-y"],
        options={poStdErrToStdOut}
      )

    var exit_code = -3
    for time_cnt in 0..timeout:
      exit_code = p.peekExitCode()
      if exit_code == -1:
        sleep(1000)
      else:
        break

    let test_result =
      case exit_code
      of -1:
        p.kill()
        TestResult.TIMEOUT
      of 0:
        TestResult.OK
      else:
        TestResult.FAIL

    echo $test_result
    write_output(p, pkg)

    let r: InstRep = (pkg.name, pkg.url, test_result)
    installation_reports.add r
    assert tmp_dir.len > 10
    removeDir(tmp_dir)


  let tstamp = $getGmTime(getTime())
  echo "Writing output"
  let page = generateHTMLPage(installation_reports, tstamp)
  writeFile("nimble_install_report.html", page)


when isMainModule:
  main()
