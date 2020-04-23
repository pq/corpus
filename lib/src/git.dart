// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:meta/meta.dart';

class CloneResult {
  final String directory;
  final int exitCode;
  final String msg;

  const CloneResult(this.exitCode, this.directory, {this.msg = ''});
}

Future<CloneResult> clone(
    {@required String repoUrl,
    @required String cloneDir,
    @required Logger logger}) async {
  var processResult;
  if (Directory(cloneDir).existsSync()) {
    logger.stdout('(Repository exists, pulling to update)');
    // todo (pq): set rebase policy?
    processResult =
        await Process.run('git', ['pull'], workingDirectory: cloneDir);
  } else {
    //logger.stdout('Cloning $repoUrl to $cloneDir');
    processResult = await Process.run(
        'git', ['clone', '--recurse-submodules', '$repoUrl.git', cloneDir]);
  }
  return CloneResult(processResult?.exitCode, cloneDir,
      msg: processResult?.stderr);
}

Future<String> getLastCommit(Directory dir) async {
  var result = await Process.run('git', ['log', '-n', '1'],
      workingDirectory: dir.absolute.path);
  return LineSplitter().convert(result.stdout).first.split(' ')[1];
}

Future<String> getLastCommitDate(Directory dir) async {
  var result = await Process.run(
      'git', ['log', '-1', '--date=iso', '--pretty=format:%cd'],
      workingDirectory: dir.absolute.path);
  return LineSplitter().convert(result.stdout).first;
}
