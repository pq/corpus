// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';

abstract class BaseCommand extends Command {
  Logger _logger;

  Logger get log =>
      _logger ??= verbose ? Logger.verbose() : Logger.standard();

  bool get verbose => globalResults['verbose'];
}
