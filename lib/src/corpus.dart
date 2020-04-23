// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Corpus model classes.
import 'dart:convert';

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
}
