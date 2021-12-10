// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Corpus model classes.
import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

import '../src/git.dart' as git;
import '../src/pub.dart' as pub;
import 'file.dart';
import 'metadata.dart';

/// A collection of projects.
class Corpus {
  /// Consider a timestamp or other Unique ID?

  final List<Project> projects = [];

  bool containsProject(String name) => getProject(name) != null;

  Project? getProject(String name) =>
      projects.firstWhereOrNull((p) => p.name == name);

  List<Map<String, dynamic>> toJson() => [
        for (var project in projects) project.toJson(),
      ];
}

/// Source hosted on Git.
class GitSource extends SourceHost {
  /// Git Repo URL.
  String? repoUrl;

  /// Commit hash used to uniquely identify this repo at a specific commit.
  String? commitHash;

  GitSource(this.repoUrl, {this.commitHash});

  static GitSource? fromJson(Map<String, dynamic> json) {
    var repoUrl = json[MetadataKeys.repoUrl];
    // No need to create a host entry with no URL.
    if (repoUrl == null) {
      return null;
    }
    var commitHash = json[MetadataKeys.commitHash];
    return GitSource(repoUrl, commitHash: commitHash);
  }

  @override
  SourceReifier<SourceHost> getReifier(Project project,
          {required String outputDirPath,
          required String overlaysPath,
          required Logger log}) =>
      GitSourceReifier(project,
          sourceDirPath: outputDirPath, overlaysPath: overlaysPath, log: log);

  @override
  Map<String, dynamic> toJson() => {
        MetadataKeys.hostKind: MetadataKeys.gitHost,
        MetadataKeys.repoUrl: repoUrl,
        MetadataKeys.commitHash: commitHash,
      };
}

class GitSourceReifier extends SourceReifier<GitSource> {
  GitSourceReifier(Project project,
      {required String overlaysPath,
      required String sourceDirPath,
      required Logger log})
      : super(project,
            sourceDirPath: sourceDirPath, overlaysPath: overlaysPath, log: log);

  @override
  Future<void> reifySources() async {
    var cloneDir = Directory(sourceDirPath);

    // If no commit info is cached, clone and capture commit metadata.
    if (host.commitHash == null) {
      log.trace('Cloning "${project.name}"...');

      var clone = await git.clone(
          repoUrl: host.repoUrl, cloneDir: sourceDirPath, logger: log);
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
    } else {
      // Checkout if needed, and set to specified commit.
      if (!cloneDir.existsSync()) {
        // Clone.
        var result = await git.clone(
            repoUrl: host.repoUrl, cloneDir: sourceDirPath, logger: log);
        if (result.exitCode == 0) {
          result = await git.checkout(
              cloneDir: sourceDirPath,
              branch: host.commitHash ?? '',
              logger: log);
        }

        if (result.exitCode != 0) {
          log.stdout('error checking out ${project.name}: ${result.msg}');
        }
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
          if (dir is Directory) {
            var pubResult = await _runPubGet(dir, overlayFiles,
                rootDir: cacheDirPath, log: log);
            if (pubResult != null && pubResult != 0) {
              // Don't set a success flag.
              continue;
            }
          }
        }

        // Tag successful pub get.
        project.metadata[MetadataKeys.pubGetSuccess] = true;

        // Copy overlays.
        if (overlayFiles.isNotEmpty) {
          var overlayRoot = Directory(path.join(overlaysPath, project.name));
          project.overlayPath =
              path.relative(overlayRoot.path, from: overlaysPath);
          log.trace('Copying overlays...');

          for (var overlayFile in overlayFiles) {
            await copyFile(overlayFile, overlayRoot,
                relativePath: path.join(cacheDirPath, project.name));
          }
        }
      }
    }
  }

  Future<int?> _runPubGet(Directory dir, List<File> overlayFiles,
      {required String rootDir, required Logger log}) async {
    var pubResult = await pub.runFlutterPubGet(dir, rootDir: rootDir, log: log);
    if (pubResult == null) {
      return null;
    }
    //yuck
    var exitCode = pubResult.result.exitCode;
    if (exitCode != 0) {
      var errorMessage = pubResult.result.stderr ?? 'no pubspec found';
      log.stderr('Error: $errorMessage');
    }

    // Copy overlay files.
    var lockFile = File(path.join(dir.path, 'pubspec.lock'));
    if (lockFile.existsSync()) {
      overlayFiles.add(lockFile);
    }

    return exitCode;
  }
}

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
      file.createSync();
    }

    await file.writeAsString(jsonString);
  }
}

/// A collected body of Dart source (package, application, etc) suitable for
/// analysis.
class Project {
  /// Project name.
  final String name;

  /// A relative path to files that should be added as an overlay to sources once
  /// they've been reified.  (Overlays might contain, for example,
  /// `pubspec.lock`, `package_config.json` files,  or other artifacts used to
  /// pin project dependencies.)
  String? overlayPath;

  /// Data on which queries can be built.
  /// For example:
  ///   * "All of the projects that have been modified in the last month."
  ///   * "All of the projects that are Flutter apps."
  ///   * "All of the projects that are Flutter web apps."
  ///   * "All of the projects that are Flutter plugins."
  ///   * "All of the projects that are vanilla Dart apps."
  ///   SDK version constraints...
  ///
  final Map<String, Object> metadata;

  /// The project's source [host].
  SourceHost? host;

  Project(this.name) : metadata = {};

  Project.fromJson(Map<String, dynamic> json)
      : name = json[MetadataKeys.projectName],
        overlayPath = json[MetadataKeys.overlayPath],
        host = SourceHost.fromJson(json[MetadataKeys.host]),
        metadata = json[MetadataKeys.metadata];

  Future<void> reifySources(
      {required String outputDirPath,
      required String overlaysPath,
      required Logger log}) async {
    var host = this.host;
    if (host == null) {
      log.trace('Not reifying $name: no source host');
      return;
    }

    var reifier = host.getReifier(this,
        outputDirPath: outputDirPath, overlaysPath: overlaysPath, log: log);
    await reifier.reifySources();
  }

  Map<String, dynamic> toJson() => {
        MetadataKeys.projectName: name,
        MetadataKeys.overlayPath: overlayPath,
        MetadataKeys.host: host?.toJson(),
        MetadataKeys.metadata: metadata,
      };
}

/// A host for project source code.
abstract class SourceHost {
  SourceHost();

  static SourceHost? fromJson(Map<String, dynamic>? json) {
    if (json != null) {
      var kind = json[MetadataKeys.hostKind];
      if (kind == MetadataKeys.gitHost) {
        return GitSource.fromJson(json);
      }
    }
    return null;
  }

  SourceReifier<SourceHost> getReifier(Project project,
      {required String outputDirPath,
      required String overlaysPath,
      required Logger log});

  Map<String, dynamic> toJson();
}

abstract class SourceReifier<T extends SourceHost> {
  final String overlaysPath;
  final String sourceDirPath;
  final Logger log;
  Project project;
  SourceReifier(this.project,
      {required this.overlaysPath,
      required this.sourceDirPath,
      required this.log});

  // todo(pq): fix this cast
  T get host => project.host as T;

  Future<void> reifySources();
}
