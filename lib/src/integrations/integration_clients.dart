/// Process-wide cache of integration clients — one instance per integration.
///
/// Mirrors the Java per-integration `getInstance()` singletons
/// (`TestRailClient.getInstance()`, `JiraClient.getInstance()`, …): every
/// integration keeps a single client (and its [Dio] transport with the
/// connection pool that goes with it) for the lifetime of the process.
/// Constructing a fresh client per tool call spins a new connection pool
/// every time — under load that surfaces as socket churn and spurious
/// timeouts (the failure mode that motivated the Java singletons).
///
/// Clients are built lazily through the standard factories and configured
/// through the standard [PropertyReader] chain. A factory whose
/// configuration is missing throws [StateError] and is **not** cached, so a
/// later access succeeds once the configuration appears.
///
/// Deliberately excluded: Teams (token-based lifecycle, not config-static)
/// and SharePoint (no config-driven factory yet).
library;

import 'package:dmtools/dmtools.dart';

/// Lazily-built, process-wide integration client singletons.
class IntegrationClients {
  IntegrationClients._();

  /// The shared cache instance.
  static final IntegrationClients instance = IntegrationClients._();

  final Map<String, Object> _cache = {};

  /// Returns the cached client for [key], building it with [build] once.
  T _cached<T extends Object>(String key, T Function() build) =>
      _cache.putIfAbsent(key, build) as T;

  /// The shared Jira client (built on first access).
  JiraClient jira() => _cached(
        'jira',
        () => JiraClient(JiraHttpClient(PropertyReader())),
      );

  /// The shared GitHub client (built on first access).
  GithubClient github() => _cached(
        'github',
        () => GithubClient(GithubHttpClient(PropertyReader())),
      );

  /// The shared GitLab client (built on first access).
  GitlabClient gitlab() => _cached(
        'gitlab',
        () => GitlabClient(GitlabHttpClient(PropertyReader())),
      );

  /// The shared Confluence client (built on first access).
  ConfluenceClient confluence() => _cached(
        'confluence',
        () => ConfluenceClient(ConfluenceHttpClient(PropertyReader())),
      );

  /// The shared Azure DevOps client (built on first access).
  AdoClient ado() => _cached(
        'ado',
        () => AdoClient(AdoHttpClient(PropertyReader())),
      );

  /// The shared TestRail client (built on first access).
  TestRailClient testrail() => _cached(
        'testrail',
        () => TestRailClient(TestRailHttpClient(PropertyReader())),
      );

  /// The shared Bitrise client (built on first access).
  BitriseClient bitrise() => _cached(
        'bitrise',
        () => BitriseClient(BitriseHttpClient(PropertyReader())),
      );

  /// The shared Jenkins client (built on first access).
  JenkinsClient jenkins() => _cached(
        'jenkins',
        () => JenkinsClient(JenkinsHttpClient(PropertyReader())),
      );

  /// The shared Figma client (built on first access).
  FigmaClient figma() => _cached(
        'figma',
        () => FigmaClient(FigmaHttpClient(PropertyReader())),
      );

  /// The shared Xray client (built on first access).
  XrayClient xray() => _cached(
        'xray',
        () => XrayClient(XrayHttpClient(PropertyReader())),
      );

  /// Drops every cached client.
  ///
  /// Production code never needs this (configuration does not change within
  /// a process); tests use it to isolate cases that reconfigure
  /// [PropertyReader] overrides.
  static void resetForTests() => instance._cache.clear();
}
