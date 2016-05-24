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
  output_dir = "nimble_install_test_output"

let version_badge_tpl = readFile "version-template-blue.svg"

type
  Pkg = tuple[name, url: string]
  TestResult* {.pure.} = enum
    OK, FAIL, TIMEOUT
  InstRep* = tuple[title, url: string, test_result: TestResult]

include "nimble_install_test_report.tmpl"
include "nimble_install_test_output.tmpl"

proc gmtime(): string =
  return $getGmTime(getTime())

proc load_packages(): seq[Pkg] =
  result = @[]
  let pkg_list = parseJson(readFile("packages.json"))
  for pdata in pkg_list:
    result.add((pdata["name"].getStr(), pdata["web"].getStr()))
  result = result.sortedByIt(it[0])
  # result = result[0..1]

proc write_status_badge(output: string, pkg: Pkg) =
  ## Write stderr/stdout output
  let page = generate_install_report_output_page(pkg.name, output, gmtime())
  writeFile(output_dir / "$#.html" % pkg.name, page)

proc extract_version(output: string, pkg: Pkg): string =
  let marker = "Installing $#-" % pkg.name
  for line in output.splitLines():
    if line.startsWith(marker):
      return line[marker.len..^1]

  return "None"

proc write_version_badge(version: string, pkg: Pkg) =
  let badge = version_badge_tpl % [version, version]
  writeFile(output_dir / "$#.version.svg" % pkg.name, badge)

proc main() =
  createDir(output_dir)

  let packages = load_packages()
  var installation_reports: seq[InstRep] = @[]

  for pkg in packages:
    let tmp_dir = "/tmp/nimble_install_test/" / pkg.name
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
    discard p.waitForExit()
    let output = p.outputStream().readAll()
    write_status_badge(output, pkg)
    if test_result == TestResult.OK:
      copyFile("success.svg", output_dir / "$#.svg" % pkg.name)
    else:
      copyFile("fail.svg", output_dir / "$#.svg" % pkg.name)

    let version = extract_version(output, pkg)
    write_version_badge(version, pkg)

    let r: InstRep = (pkg.name, pkg.url, test_result)
    installation_reports.add r
    assert tmp_dir.len > 10
    removeDir(tmp_dir)


  let tstamp = $getGmTime(getTime())
  echo "Writing output"
  let page = generateHTMLPage(installation_reports, tstamp)
  writeFile(output_dir / "nimble_install_report.html", page)


when isMainModule:
  main()
