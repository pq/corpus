// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

/// Staleness check

// curl rest api?
// https://stackoverflow.com/questions/25563455/how-do-i-get-last-commit-date-from-git-repository/51403241

//////////////

/// A host for project source code.
abstract class SourceHost {}

/// 1-2 quarter goals
/// Need to come to an understanding about the mix of the corpus
/// Want to make sure Google3 customers are amply represented
/// Want to make sure non-Flutter apps are represented

/// General goals
/// Customer mix
/// Maintenance
///   * what are long term maintenance issues?  How can we mitigate?
///   * can the tooling be self-healing?

/// Source hosted on Github.
class GithubSource extends SourceHost {
  /// Github Repo URL.
  String repoUrl;

  /// ...
  String commitSha;

  /// A [DateTime]-formatted date that marks when this source was last updated.
  /// => metadata
  ///String lastModified;
}

/// TODO: fill this out.
class Google3Source extends SourceHost {
  /// Ooof.  How do ACLs bear on this?
}

class BitBucketSource extends SourceHost {}

class PubDevPackageSource extends SourceHost {
  /// zipLocation
}

/// A collection of projects.
class Corpus {
  List<Project> projects;
}

/// A collected body of Dart source (package, application, etc) suitable for
/// analysis.
class Project {
  /// Project name.
  String name;

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
  Map<String, Object> metadata;

  /// The project's source [host].
  SourceHost host;
}

/// 0. fetch feed
/// 1. iterate and clone (removing non-github repo urls)
/// 2. iterate over cloned repos and (recursively) exec `flutter pub get`
/// 3. discard repos who's deps can't be satisfied (or have not been touched in n months)
/// 4. iterate over repos and
///    a. copy all `pubspec.lock`s into an overlay directory, and
///    b. store name, SHA of checked out commit, repo_url and a pointer to overlay directories
Future<void> main() async {
  var feed = File('../../_data/itsallwidgets/feed.json').readAsStringSync();
  var count = 0;
  for (var entry in json.decode(feed)) {
    var name = entry['url'].split('/').last;
    var repo = entry['repo_url'];
    print('$name: $repo');
    ++count;
  }

  print(count);

  var commit = await getLastCommitDate(Directory.current);
  print(commit);

  var d = DateTime.parse(commit);
  print(d);
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
