// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:analyzer/source/line_info.dart';

import '../file.dart';

/// A simple visitor for analysis options files.
abstract class AnalysisOptionsVisitor {
  void visit(AnalysisOptionsFile file) {}
}

class OptionsVisitor extends AnalysisOptionsVisitor {
  @override
  void visit(AnalysisOptionsFile options) {
    //print('>> visiting: ${options.file}');
  }
}

/// A simple visitor for pubspec files.
abstract class PubspecVisitor {
  void visit(PubspecFile file) {}
}
