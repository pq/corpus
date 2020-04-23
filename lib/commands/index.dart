// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';

import 'index/itsallwidgets.dart';

class IndexCommand extends Command {
  IndexCommand() {
    addSubcommand(IndexItsAllWidgetsCommand());
  }

  @override
  String get name => 'index';

  @override
  String get description => 'Build corpus indexes.';
}
