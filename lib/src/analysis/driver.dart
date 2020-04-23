// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/generated/engine.dart' // ignore: implementation_imports
    show
        AnalysisEngine;
import 'package:cli_util/cli_logging.dart';
import 'package:path/path.dart' as path;

import '../file.dart';
import 'visitors.dart';

/// Returns a [Future] that completes after the [event loop][] has run the given
/// number of [times] (20 by default).
///
/// [event loop]: https://webdev.dartlang.org/articles/performance/event-loop#darts-event-loop-and-queues
///
/// Awaiting this approximates waiting until all asynchronous work (other than
/// work that's waiting for external resources) completes.
Future _pumpEventQueue({int times}) {
  times ??= 20;
  if (times == 0) return Future.value();
  // Use [new Future] future to allow microtask events to finish. The [new
  // Future.value] constructor uses scheduleMicrotask itself and would therefore
  // not wait for microtask callbacks that are scheduled after invoking this
  // method.
  return Future(() => _pumpEventQueue(times: times - 1));
}

class Driver {
  final List<String> sources;
  final Logger log;
  List<String> _excludedPaths;

  bool resolveUnits = true;

  /// Hook to contribute a custom AST visitor.
  AstVisitor visitor;

  /// Hook to contribute custom pubspec analysis.
  PubspecVisitor pubspecVisitor;

  Driver(this.sources, this.log);

  /// List of paths to exclude from analysis.
  List<String> get excludedPaths => _excludedPaths ?? [];

  /// List of paths to exclude from analysis.
  /// For example:
  /// ```
  ///   driver.excludedPaths = ['example', 'test'];
  /// ```
  /// excludes package `example` and `test` directories.
  set excludedPaths(List<String> excludedPaths) {
    _excludedPaths = excludedPaths;
  }

  Future analyze() => _analyze(sources);

  Future _analyze(List<String> sourceDirs) async {
    if (sourceDirs.isEmpty) {
      log.stderr('Specify one or more files and directories.');
      return;
    }
    ResourceProvider resourceProvider = PhysicalResourceProvider.INSTANCE;
    await _analyzeFiles(resourceProvider, sourceDirs);
    log.stdout('Finished.');
  }

  Future _analyzeFiles(
      ResourceProvider resourceProvider, List<String> analysisRoots) async {
    if (excludedPaths.isNotEmpty) {
      log.stdout('(Excluding paths $excludedPaths from analysis.)');
    }

    // Analyze.
    log.stdout('Analyzing...');

    for (var root in analysisRoots) {
      var collection = AnalysisContextCollection(
        includedPaths: [root],
        excludedPaths: excludedPaths.map((p) => path.join(root, p)).toList(),
        resourceProvider: resourceProvider,
      );

      for (var context in collection.contexts) {
        for (var filePath in context.contextRoot.analyzedFiles()) {
          if (AnalysisEngine.isDartFileName(filePath)) {
            try {
              var result = resolveUnits
                  ? await context.currentSession.getResolvedUnit(filePath)
                  : context.currentSession.getParsedUnit(filePath);

              if (visitor != null) {
                if (result is ParsedUnitResult) {
                  result.unit.accept(visitor);
                } else if (result is ResolvedUnitResult) {
                  result.unit.accept(visitor);
                }
              }
            } catch (e) {
              log.stderr('Exception caught analyzing: $filePath');
              log.stderr(e.toString());
            }
          } else {
            if (pubspecVisitor != null) {
              if (path.basename(filePath) == AnalysisEngine.PUBSPEC_YAML_FILE) {
                pubspecVisitor.visit(PubspecFile(filePath));
              }
            }
          }
        }
        await _pumpEventQueue(times: 512);
      }
    }
  }
}
