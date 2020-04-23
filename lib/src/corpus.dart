// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Corpus model classes.
import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../src/git.dart' as git;
import '../src/pub.dart' as pub;
import 'file.dart';
import 'metadata.dart';

/// A collection of projects.
class Corpus {
  /// Consider a timestamp or other Unique ID?

  final List<Project> projects = [];

  Project getProject(String name) =>
      projects.firstWhere((p) => p.name == name, orElse: () => null);

  bool containsProject(String name) => getProject(name) != null;

  List<Map<String, dynamic>> toJson() => [
        for (var project in projects) project.toJson(),
      ];
}

abstract class SourceReifier<T extends SourceHost> {
  final String overlaysPath;
  final String sourceDirPath;
  final Logger log;
  Project project;
  SourceReifier(this.project,
      {@required this.overlaysPath,
      @required this.sourceDirPath,
      @required this.log});

  Future<void> reifySources();

  T get host => project.host;
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
      await file.create();
    }

    await file.writeAsString(jsonString);
  }
}


class GithubSourceReifier extends SourceReifier<GithubSource> {
  GithubSourceReifier(Project project,
      {@required String overlaysPath,
      @required String sourceDirPath,
      @required Logger log})
      : super(project,
            sourceDirPath: sourceDirPath, overlaysPath: overlaysPath, log: log);

  @override
  Future<void> reifySources() async {
    var cloneDir = Directory(sourceDirPath);

    // If no commit info is cached, clone and capture commit metadata.
    if (host.commitHash == null) {
      log.stdout('Cloning "${project.name}"...');

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
          var overlayRoot = Directory(path.join(overlaysPath, project.name));
          project.overlayPath =
              path.relative(overlayRoot.path, from: overlaysPath);
          log.stdout('Copying overlays...');

          for (var overlayFile in overlayFiles) {
            await copyFile(overlayFile, overlayRoot,
                relativePath: path.join(cacheDirPath, project.name));
          }
        }
      }
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
}

/// Source hosted on Github.
class GithubSource extends SourceHost {
  /// Github Repo URL.
  String repoUrl;

  /// Commit hash used to uniquely identify this repo at a specific commit.
  String commitHash;

  GithubSource(this.repoUrl, {this.commitHash});

  factory GithubSource.fromJson(Map<String, dynamic> json) {
    var repoUrl = json[MetadataKeys.repoUrl];
    // No need to create a host entry with no URL.
    if (repoUrl == null) {
      return null;
    }
    var commitHash = json[MetadataKeys.commitHash];
    return GithubSource(repoUrl, commitHash: commitHash);
  }

  @override
  Map<String, dynamic> toJson() => {
        MetadataKeys.hostKind: MetadataKeys.githubHost,
        MetadataKeys.repoUrl: repoUrl,
        MetadataKeys.commitHash: commitHash,
      };

  @override
  SourceReifier<SourceHost> getReifier(Project project,
          {String outputDirPath, String overlaysPath, Logger log}) =>
      GithubSourceReifier(project,
          sourceDirPath: outputDirPath, overlaysPath: overlaysPath, log: log);
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
  String overlayPath;

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
  SourceHost host;

  Project(this.name) : metadata = {};

  Future<void> reifySources(
      {@required String outputDirPath,
      @required String overlaysPath,
      @required Logger log}) async {
    if (host == null) {
      log.stdout('Not reifying $name: no source host');
      return;
    }

    //
    var reifier = host.getReifier(this,
        outputDirPath: outputDirPath, overlaysPath: overlaysPath, log: log);
    await reifier.reifySources();
  }

  Project.fromJson(Map<String, dynamic> json)
      : name = json[MetadataKeys.projectName],
        overlayPath = json[MetadataKeys.overlayPath],
        host = SourceHost.fromJson(json[MetadataKeys.host]),
        metadata = jsonDecode(json[MetadataKeys.metadata]);

  Map<String, dynamic> toJson() => {
        MetadataKeys.projectName: name,
        MetadataKeys.overlayPath: overlayPath,
        MetadataKeys.host: host?.toJson(),
        MetadataKeys.metadata: jsonEncode(metadata),
      };
}

/// A host for project source code.
abstract class SourceHost {
  Map<String, dynamic> toJson();

  SourceHost();

  factory SourceHost.fromJson(Map<String, dynamic> json) {
    if (json != null) {
      var kind = json[MetadataKeys.hostKind];
      if (kind == MetadataKeys.githubHost) {
        return GithubSource.fromJson(json);
      }
    }
    return null;
  }

  SourceReifier<SourceHost> getReifier(Project project,
      {String outputDirPath, String overlaysPath, Logger log});
}
