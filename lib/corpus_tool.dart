// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'commands/fetch.dart';
import 'commands/index.dart';

class CorpusToolCommandRunner extends CommandRunner {
  CorpusToolCommandRunner()
      : super('corpus_tool', 'Flutter corpus tools.') {
    addCommand(FetchCommand());
    addCommand(IndexCommand());
  }
}
