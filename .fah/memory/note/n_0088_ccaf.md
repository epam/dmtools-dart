---
id: "n_0088_ccaf"
type: "note"
title: "dmtools-dart workflow builds the tool from the source checkout (`dart pub get && make native`, then `dart run bin/dmtools.dart`) instead of the release binary, because the release lacks PR #18 features; Flutter 3.44.4 is installed via subosito/flutter-action@v2 with cache (overridable via vars.FLUTTER_VERSION) though dmtools-dart itself is pure Dart."
author: "agent"
date: "2026-09-08T19:37:01.470201Z"
area: "project"
topics: []
source: "agent"
accessCount: 0
importance: 0.7
tags: ["#note", "#source_agent", "build-from-source", "flutter-action"]
---


# Note: n_0088_ccaf

dmtools-dart workflow builds the tool from the source checkout (`dart pub get && make native`, then `dart run bin/dmtools.dart`) instead of the release binary, because the release lacks PR #18 features; Flutter 3.44.4 is installed via subosito/flutter-action@v2 with cache (overridable via vars.FLUTTER_VERSION) though dmtools-dart itself is pure Dart.

**By:** [[agent]]
**Date:** 2026-09-08T19:37:01.470201Z
**Area:** [[project|project]]
