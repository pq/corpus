// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../corpus.dart';
import '../pub.dart' as pub;
import 'base.dart';

class FetchCommand extends BaseCommand {
  static const cacheDirPath = '_cache';
  static const indexDirPath = '_index';

  FetchCommand() {
    argParser.addOption('limit', abbr: 'l', defaultsTo: '0');
  }

  @override
  String get description => 'Fetch corpus contents.';

  int get fetchLimit => int.parse(argResults!['limit']);

  @override
  String get name => 'fetch';

  @override
  Future run() async {
    var args = argResults!.rest;
    if (args.isEmpty) {
      // todo (pq): print message
      return null;
    }

    log.stdout('Reading index...');
    var indexName = args[0];
    var indexFile = path.join(indexDirPath, indexName, 'index.json');
    var index = IndexFile(indexFile)..readSync();

    log.stdout('Fetching...');
    if (fetchLimit > 0) {
      log.stdout('(Fetch limit set to $fetchLimit)');
    }

    var fetched = 0;

    var overlaysDirPath = path.join(indexDirPath, indexName, 'overlays');
    for (var project in index.corpus.projects) {
      if (++fetched > fetchLimit) {
        log.stdout('(Fetch limit reached)');
        break;
      }
      log.trace('Fetching ${project.name}...');
      var cloneDirPath = path.join(cacheDirPath, project.name);
      await project.reifySources(
          outputDirPath: cloneDirPath, overlaysPath: overlaysDirPath, log: log);
      await pub.runFlutterPubGet(Directory(cloneDirPath),
          rootDir: cacheDirPath, log: log);
    }

    log.stdout('Done');
  }
}
