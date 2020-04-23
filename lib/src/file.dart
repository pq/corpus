// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

const cacheDirPath = '_cache';
const indexDirPath = '_index';

class AnalysisOptionsFile {
  final File file;

  String _contents;

  YamlMap _yaml;
  AnalysisOptionsFile(String path) : file = File(path);

  String get contents => _contents ??= file.readAsStringSync();

  /// Can throw a [FormatException] if yaml is malformed.
  YamlMap get yaml => _yaml ??= _readYamlFromString(contents);
}

class PubspecFile {
  final File file;

  String _contents;

  YamlMap _yaml;
  PubspecFile(String path) : file = File(path);

  String get contents => _contents ??= file.readAsStringSync();

  /// Can throw a [FormatException] if yaml is malformed.
  YamlMap get yaml => _yaml ??= _readYamlFromString(contents);
}

YamlMap _readYamlFromString(String optionsSource) {
  if (optionsSource == null) {
    return YamlMap();
  }
  try {
    var doc = loadYamlNode(optionsSource);
    if (doc is YamlMap) {
      return doc;
    }
    return YamlMap();
  } on YamlException catch (e) {
    throw FormatException(e.message, e.span);
  } catch (e) {
    throw FormatException('Unable to parse YAML document.');
  }
}




/// Recursive copy [src] to [dest].
Future<void> copy(FileSystemEntity src, Directory dest) async {
  if (src is File) {
    await copyFile(src, dest);
  } else {
    await _copyDir(src, dest);
  }
}

Future<void> copyFile(File src, Directory dest, {String relativePath}) async {
  var filePath = path.relative(src.path, from: relativePath);
  var file = await File(path.join(dest.path, filePath)).create(recursive: true);
  await src.copy(file.path);
}

Future<void> _copyDir(Directory src, Directory dest) async {
  await for (var entity in src.list()) {
    var p = path.join(dest.absolute.path, path.basename(entity.path));
    if (entity is Directory) {
      var dir = await Directory(p).create();
      await copy(entity.absolute, dir);
    } else if (entity is File) {
      await entity.copy(p);
    }
  }
}
