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
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../../src/analysis/driver.dart';
import '../../src/analysis/visitors.dart';
import '../../src/corpus.dart';
import '../../src/file.dart';
import '../../src/git.dart' as git;
import '../../src/metadata.dart';
import '../../src/pub.dart' as pub;

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

class IndexFile {
  final Corpus corpus = Corpus();

  final File file;
  IndexFile(String path) : file = File(path);

  bool readSync() {
    if (file.existsSync()) {
      var index = file.readAsStringSync();
      for (var entry in json.decode(index)) {
        var project = Project.fromJson(entry);
        corpus.projects.add(project);
      }
      return true;
    }
    return false;
  }

  Future<void> write({bool prettyPrint = true}) async {
    var jsonMap = corpus.toJson();
    var jsonString = prettyPrint
        ? JsonEncoder.withIndent('  ').convert(jsonMap)
        : jsonEncode(jsonMap);
    if (!file.existsSync()) {
      await file.create();
    }

    await file.writeAsString(jsonString);
  }
}

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

    var limit = 2;

    // todo (pq): MOVE

    log.stdout('Fetching projects...');

    var count = 0;
    for (var project in corpus.projects) {
      //TMP
      if (++count > limit) {
        break;
      }

      
      var cloneDirPath = path.join(cacheDirPath, project.name);
      var cloneDir = Directory(cloneDirPath);
      var host = project.host as GithubSource;

      // Skip invalid hosts (indicates an invalid repo URL).
      if (host == null) {
        log.stdout('Skipping ${project.name}: invalid repo url');
        continue;
      }

      // If no commit info is cached, clone and capture commit metadata.
      if (host.commitHash == null) {
        log.stdout('Cloning "${project.name}"...');

        var clone = await git.clone(
            repoUrl: host.repoUrl, cloneDir: cloneDirPath, logger: log);
        if (clone.exitCode != 0) {
          log.stderr('Error cloning ${project.name}: ${clone.msg}');
          // Set repo URl to null to prevent retries.
          host.repoUrl = null;
        } else {
          //
          // Cache commit metadata.
          var lastCommit = await git.getLastCommit(cloneDir);
          var commitDate = await git.getLastCommitDate(cloneDir);
          project.metadata[MetadataKeys.lastCommitDate] = commitDate;
          host.commitHash = lastCommit;
        }
      }

      // If no overlayPath is cached, get pub deps and cache overlays.
      if (project.overlayPath == null) {
        //
        // Get pub dependencies.
        var overlayFiles = <File>[];
        var pubResult = await _runPubGet(cloneDir, overlayFiles,
            rootDir: cacheDirPath, log: log);
        // todo (pq): this won't work w/ mono_repos: FIX that.
        if (pubResult == 0) {
          for (var dir in cloneDir.listSync(recursive: true)) {
            var pubResult = await _runPubGet(dir, overlayFiles,
                rootDir: cacheDirPath, log: log);
            if (pubResult != null && pubResult != 0) {
              // Don't set a success flag.
              continue;
            }
          }

          // Tag successful pub get.
          project.metadata[MetadataKeys.pubGetSuccess] = true;

          // Copy overlays.
          if (overlayFiles.isNotEmpty) {
            var overlayRoot =
                Directory(path.join(_overlaysDirPath, project.name));
            project.overlayPath =
                path.relative(overlayRoot.path, from: _overlaysDirPath);
            log.stdout('Copying overlays...');

            for (var overlayFile in overlayFiles) {
              await copyFile(overlayFile, overlayRoot,
                  relativePath: path.join(cacheDirPath, project.name));
            }
          }
        }
      }

      //
      // Perform analysis if necessary.
      var analysisPerformed =
          project.metadata[MetadataKeys.libraryCount] != null;
      if (!analysisPerformed || true /* TMP */) {
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

//    var rawJson = corpus.toJson();
//    var prettyJson = JsonEncoder.withIndent('  ').convert(rawJson);

    // todo (pq): push into IndexFile

    log.stdout('Writing index...');
    await index.write();
  }
}

Future<int> _runPubGet(FileSystemEntity dir, List<File> overlayFiles,
    {@required String rootDir, @required Logger log}) async {
  var pubResult = await pub.runFlutterPubGet(dir, rootDir: rootDir, log: log);
  if (pubResult == null) {
    return null;
  }
  //yuck
  var exitCode = pubResult.result.exitCode;
  if (exitCode != 0) {
    var errorMessage = pubResult?.result?.stderr ?? 'no pubspec found';
    log.stderr('Error: $errorMessage');
  }

  // Copy overlay files.
  var lockFile = File(path.join(dir.path, 'pubspec.lock'));
  if (lockFile.existsSync()) {
    overlayFiles.add(lockFile);
  }

  return exitCode;
}
