/// Request shapes, batching, and download-cache helpers shared by the
/// async [FigmaClient] and the sync JS-surface executors — the parts of
/// the Java `FigmaClient` tool methods that are transport-independent.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'figma_url.dart';

/// The `node-id` query parameter name shared by every design-URL tool.
const figmaNodeIdParam = 'node-id';

/// JSON `null` literal for the sync bridge — Java tools that return `null`
/// serialize to this on the wire.
const figmaJsonNull = 'null';

/// Render batch size — Java `renderNodes` sends at most 100 ids per call.
const figmaRenderBatchSize = 100;

/// `figma_get_node_details` id cap (Java `Arrays.copyOf(ids, 10)`).
const figmaMaxDetailIds = 10;

/// `figma_get_text_content` id cap (Java `Arrays.copyOf(ids, 20)`).
const figmaMaxTextIds = 20;

/// A resolved API request: path plus query parameters.
typedef FigmaRequest = ({String path, Map<String, String> params});

/// Resolves the structure request for a design URL — Java
/// `getFileStructure` branching: a URL `node-id` selects the
/// `files/{fileId}/nodes` subtree; otherwise the full file is fetched with
/// size-limiting params.
FigmaRequest figmaStructureRequest(String cleanHref) {
  final fileId = figmaParseFileId(cleanHref);
  final nodeId = _optionalNodeId(cleanHref);
  if (nodeId != null && nodeId.isNotEmpty) {
    return (path: 'files/$fileId/nodes', params: {'ids': nodeId});
  }
  return (path: 'files/$fileId', params: const {
    'geometry': 'paths',
    'depth': '2',
  });
}

/// The URL's `node-id` value, or `null` when absent.
String? _optionalNodeId(String cleanHref) {
  try {
    return figmaExtractQueryParam(cleanHref, figmaNodeIdParam);
  } on StateError {
    return null;
  }
}

/// Render request params for `figma_download_node_image` — Java parity:
/// ids, format, and an explicit scale (default 2) in every request.
Map<String, String> figmaRenderParams(
  String nodeId,
  String format,
  int scale,
) =>
    {'ids': nodeId, 'format': format, 'scale': '$scale'};

/// Render request params for `getImageById` — Java parity: a 2x scale is
/// added only for png exports.
Map<String, String> figmaIconRenderParams(String nodeId, String format) =>
    format == 'png'
        ? {'ids': nodeId, 'format': format, 'scale': '2'}
        : {'ids': nodeId, 'format': format};

/// Splits [ids] into consecutive batches of at most [size] — Java
/// `renderNodes` batching.
List<List<String>> figmaBatches(List<String> ids,
    [int size = figmaRenderBatchSize]) {
  return [
    for (var i = 0; i < ids.length; i += size)
      ids.sublist(i, min(i + size, ids.length)),
  ];
}

/// Splits a comma-separated id list, trims each entry, and caps the result
/// at [max] (Java `Arrays.copyOf` parity).
List<String> figmaCappedTrimmedIds(String nodeIds, int max) {
  final ids = nodeIds.split(',').map((id) => id.trim()).toList();
  return ids.length > max ? ids.sublist(0, max) : ids;
}

/// Cache file for a download URL — Java `getCachedFile` parity: md5-named,
/// `.png` suffix when the URL contains "images".
File figmaCacheFileFor(String url, String cacheDir) {
  final name = md5.convert(utf8.encode(url)).toString();
  final suffix = url.contains('images') ? '.png' : '';
  final dir = Directory(cacheDir)..createSync(recursive: true);
  return File('${dir.path}/$name$suffix');
}
