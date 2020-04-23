// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:path/path.dart' as path;

import '../../src/analysis/driver.dart';
import '../../src/analysis/visitors.dart';
import '../../src/corpus.dart';
import '../../src/file.dart';
import '../../src/metadata.dart';

class _AstVisitor extends SimpleAstVisitor<void> {
  final Set<LibraryElement> libraries = {};

  int lineCount = 0;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    var element = node.declaredElement;
    var library = element.library;
    libraries.add(library);
    lineCount += element.lineInfo.lineCount;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    print(node.name);
    print(node.declaredElement);
  }
}

class _PubspecVisitor extends PubspecVisitor {
  String sdkConstraint;

  @override
  void visit(PubspecFile file) {
    sdkConstraint = (file.yaml['environment'] ?? {})['sdk'];
  }
}

final _overlaysDirPath = path.join(indexDirPath, 'itsallwidgets', 'overlays');
final _indexFilePath = path.join(indexDirPath, 'itsallwidgets', 'index.json');
final _feedFilePath = path.join('_data', 'itsallwidgets', 'feed.json');

class IndexItsAllWidgetsCommand extends Command {
  @override
  String get name => 'itsallwidgets';

  @override
  String get description => 'Build itsallwidgets index.';

  @override
  Future run() async {
    var log = Logger.standard();
    log.stdout('Building index...');

    // Read or create the index.
    var index = IndexFile(_indexFilePath)..readSync();
    var corpus = index.corpus;

    // Update index with data from the itsallwidgets RSS feed.

    log.stdout('Parsing feed...');
    var feed = File(_feedFilePath).readAsStringSync();
    for (var entry in json.decode(feed)) {
      var name = entry['url'].split('/').last;
      // Add.
      if (!corpus.containsProject(name)) {
        var project = Project(name);
        var repo = entry['repo_url'];
        project.host = GithubSource(repo);
        corpus.projects.add(project);
      }
      // todo (pq): remove projects not in feed
    }


    log.stdout('Fetching projects...');

    //TMP
    var limit = 2;
    var count = 0;

    for (var project in corpus.projects) {
      //TMP
      if (++count > limit) {
        break;
      }

      if (project.host == null) {
        log.stdout('Skipping ${project.name}: no source host');
        continue;
      }

      var cloneDirPath = path.join(cacheDirPath, project.name);
      await project.reifySources(
          outputDirPath: cloneDirPath,
          overlaysPath: _overlaysDirPath,
          log: log);

      //
      // Perform analysis if necessary.
      var analysisPerformed =
          project.metadata[MetadataKeys.libraryCount] != null;
      if (!analysisPerformed || true /* TMP */) {
        var cloneDir = Directory(cloneDirPath);
        // todo (pq): do we need to recurse here?
        var driver = Driver([cloneDir.absolute.path], log);
        var astVisitor = _AstVisitor();
        driver.visitor = astVisitor;
        var pubspecVisitor = _PubspecVisitor();
        driver.pubspecVisitor = pubspecVisitor;
        await driver.analyze();

        project.metadata[MetadataKeys.libraryCount] =
            astVisitor.libraries.length;
        project.metadata[MetadataKeys.lineCount] = astVisitor.lineCount;

        project.metadata[MetadataKeys.sdkConstraint] =
            pubspecVisitor.sdkConstraint;
      }
    }

    log.stdout('Writing index...');
    await index.write();
  }
}
