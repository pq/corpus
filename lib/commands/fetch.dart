// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:args/command_runner.dart';

class FetchCommand extends Command {
  @override
  String get name => 'fetch';

  @override
  String get description => 'Fetch corpus contents.';

  @override
  Future run() async {}
}
