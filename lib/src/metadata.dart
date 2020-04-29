// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

class MetadataKeys {
  // todo (pq): consider shortening these key values to reduce the size of index.json
  static const String commitHash = 'commitHash';
  static const String gitHost = 'git';
  static const String host = 'host';
  static const String hostKind = 'kind';
  static const String lastCommitDate = 'lastCommitDate';
  static const String libraryCount = 'libraryCount';
  static const String lineCount = 'loc';
  static const String metadata = 'metadata';
  static const String overlayPath = 'overlayPath';
  static const String projectName = 'name';
  static const String pubGetSuccess = 'pubGetSuccess';
  static const String repoUrl = 'repoUrl';
  static const String sdkConstraint = 'sdkConstraint';
}
