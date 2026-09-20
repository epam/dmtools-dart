import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

import 'figma_test_support.dart';

/// Serves `{}` for every request.
String spyRouter(RequestOptions o) => '{}';

/// A spy client plus the executor bound to it.
typedef ExecutorFixture = ({FigmaToolExecutor executor, SpyFigmaClient spy});

/// Builds a [SpyFigmaClient] over the mocked transport and wraps it.
ExecutorFixture executorFixture() {
  final spy = SpyFigmaClient(mockFigmaHttp(spyRouter).http);
  return (executor: FigmaToolExecutor(spy), spy: spy);
}

/// Records every dispatched call; URL-based Java-parity methods stub their
/// results instead of hitting the transport so routing tests stay pure.
class SpyFigmaClient extends FigmaClient {
  /// Creates the spy over [http].
  SpyFigmaClient(super.http);

  /// Recorded calls, most recent last.
  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<String> meJson() {
    calls.add('meJson');
    return super.meJson();
  }

  @override
  Future<String?> getImageOfSource(String url) async {
    calls.add('getImageOfSource:$url');
    return null;
  }

  @override
  Future<String?> downloadNodeImage(
    String href,
    String nodeId, {
    String? format,
    int? scale,
  }) async {
    calls.add('downloadNodeImage:$href:$nodeId:$format:$scale');
    return null;
  }

  @override
  Future<String?> convertUrlToFile(String href) async {
    calls.add('convertUrlToFile:$href');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getFileStructure(String href) async {
    calls.add('getFileStructure:$href');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getIcons(String href) async {
    calls.add('getIcons:$href');
    return null;
  }

  @override
  Future<String> getImageFills(String href) async {
    calls.add('getImageFills:$href');
    return '';
  }

  @override
  Future<String> renderNodes(
    String href,
    String nodeIds, {
    String? format,
  }) async {
    calls.add('renderNodes:$href:$nodeIds:$format');
    return '';
  }

  @override
  Future<String?> downloadIconFile(
    String href,
    String nodeId,
    String format,
  ) async {
    calls.add('downloadIconFile:$href:$nodeId:$format');
    return null;
  }

  @override
  Future<String?> getSvgContent(String href, String nodeId) async {
    calls.add('getSvgContent:$href:$nodeId');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getNodeDetails(String href, String nodeIds) async {
    calls.add('getNodeDetails:$href:$nodeIds');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getTextContent(String href, String nodeIds) async {
    calls.add('getTextContent:$href:$nodeIds');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getDesignStyles(String href) async {
    calls.add('getDesignStyles:$href');
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getLayers(String href) async {
    calls.add('getLayers:$href');
    return null;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getLayersBatch(
    String href,
    String nodeIds,
  ) async {
    calls.add('getLayersBatch:$href:$nodeIds');
    return {};
  }

  @override
  Future<Map<String, dynamic>?> getNodeChildren(String href) async {
    calls.add('getNodeChildren:$href');
    return null;
  }

  @override
  Future<List<dynamic>> listTeamProjects(String teamIdOrUrl) async {
    calls.add('listTeamProjects:$teamIdOrUrl');
    return const [];
  }

  @override
  Future<List<dynamic>> listProjectFiles(String projectIdOrUrl) async {
    calls.add('listProjectFiles:$projectIdOrUrl');
    return const [];
  }

  @override
  Future<List<dynamic>> getFileComments(String href) async {
    calls.add('getFileComments:$href');
    return const [];
  }

  @override
  Future<Map<String, dynamic>> getFile(String key) {
    calls.add('getFile:$key');
    return super.getFile(key);
  }

  @override
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) {
    calls.add('getFileNodes:$key:$nodeIds');
    return super.getFileNodes(key, nodeIds);
  }

  @override
  Future<Map<String, dynamic>> getImage(String key, String nodeId) {
    calls.add('getImage:$key:$nodeId');
    return super.getImage(key, nodeId);
  }

  @override
  Future<Map<String, dynamic>> getComments(String key) {
    calls.add('getComments:$key');
    return super.getComments(key);
  }

  @override
  Future<Map<String, dynamic>> postComment(String key, String message) {
    calls.add('postComment:$key:$message');
    return super.postComment(key, message);
  }

  @override
  Future<Map<String, dynamic>> getComponents(String key) {
    calls.add('getComponents:$key');
    return super.getComponents(key);
  }

  @override
  Future<Map<String, dynamic>> getComponentSets(String key) {
    calls.add('getComponentSets:$key');
    return super.getComponentSets(key);
  }

  @override
  Future<Map<String, dynamic>> exportImage(
    String key, {
    String? format,
    double? scale,
  }) {
    calls.add('exportImage:$key:$format:$scale');
    return super.exportImage(key, format: format, scale: scale);
  }

  @override
  Future<Map<String, dynamic>> getVariableCollections(String key) {
    calls.add('getVariableCollections:$key');
    return super.getVariableCollections(key);
  }

  @override
  Future<Map<String, dynamic>> getLibraryComponents(String libraryKey) {
    calls.add('getLibraryComponents:$libraryKey');
    return super.getLibraryComponents(libraryKey);
  }

  @override
  Future<Map<String, dynamic>> getStyle(String key) {
    calls.add('getStyle:$key');
    return super.getStyle(key);
  }

  @override
  Future<Map<String, dynamic>> getNode(String key, String nodeId) {
    calls.add('getNode:$key:$nodeId');
    return super.getNode(key, nodeId);
  }
}
