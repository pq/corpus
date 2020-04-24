// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

var _packageConfigPath = path.join('.dart_tool', 'package_config.json');

bool _hasPubspec(FileSystemEntity f) =>
    f is Directory && File(path.join(f.path, 'pubspec.yaml')).existsSync();

class PubGetResult {
  /// Directory where pub was run.
  Directory directory;

  /// Process result of running pub.
  ProcessResult result;

  PubGetResult(this.directory, this.result);
}

Future<PubGetResult> runFlutterPubGet(FileSystemEntity dir,
    {bool skipUpdate = false, @required String rootDir, Logger log}) async {
  log ??= Logger.standard();
  if (_hasPubspec(dir)) {
    var packageFile = path.join(dir.path, _packageConfigPath);
    // todo (pq): fix update logic
    if (!File(packageFile).existsSync() || !skipUpdate) {
      log.stdout(
          "Getting pub dependencies for '${path.relative(dir.path, from: rootDir)}'...");
      var processResult = await Process.run('flutter', ['pub', 'get'],
          workingDirectory: dir.path);
      return PubGetResult(dir, processResult);
    }
  }
  return null;
}
