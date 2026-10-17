import 'dart:convert';

import 'package:dmtools/src/config/property_names.dart';
import 'package:dmtools/src/env/js_env_policy.dart';
import 'package:dmtools/src/integrations/env/env_tools.dart';
import 'package:test/test.dart';

/// Java `EnvToolsTest` parity. Values come from an in-memory map; a lookup
/// counter proves refused and invalid names never reach the value source.
void main() {
  late Map<String, String> values;
  late List<String> lookups;
  late EnvTools tools;

  setUp(() {
    values = {};
    lookups = [];
    tools = EnvTools(
      lookup: (key) {
        lookups.add(key);
        return values[key];
      },
    );
  });

  Map<String, dynamic> get(String name) =>
      jsonDecode(tools.envGet(name)) as Map<String, dynamic>;

  test('allowed name returns its value', () {
    values['ADO_PROJECT'] = 'PROJ';
    expect(get('ADO_PROJECT'), {'name': 'ADO_PROJECT', 'value': 'PROJ'});
  });

  test('lookup is case-insensitive', () {
    values['ADO_PROJECT'] = 'PROJ';
    expect(get('ado_project')['value'], 'PROJ');
  });

  test('unset allowed name answers value null', () {
    expect(get('ADO_PROJECT'), {'name': 'ADO_PROJECT', 'value': null});
  });

  test('secret is refused without its value and without a secret lookup', () {
    values['JIRA_API_TOKEN'] = 'REAL-SECRET';
    final out = tools.envGet('JIRA_API_TOKEN');
    expect(out, isNot(contains('REAL-SECRET')));
    expect(get('JIRA_API_TOKEN').containsKey('error'), isTrue);
    expect(lookups, isNot(contains('JIRA_API_TOKEN')));
  });

  test('invalid names are rejected without a lookup', () {
    for (final bad in [null, '', '1X', 'A-B', 'A.B']) {
      final out = jsonDecode(tools.envGet(bad)) as Map<String, dynamic>;
      expect(out['error'], contains('invalid name'), reason: '$bad');
    }
    // Only the allowlist key may be read for an invalid name, never the name.
    expect(lookups.every((k) => k == JsEnvPolicy.allowlistKey), isTrue);
  });

  test('not-allowlisted name is refused', () {
    expect(get('RANDOM_THING')['error'], contains('JS_ENV_ALLOWLIST'));
  });

  test('JS_ENV_ALLOWLIST makes a custom name readable', () {
    values[JsEnvPolicy.allowlistKey] = 'MY_CUSTOM';
    values['MY_CUSTOM'] = 'hello';
    expect(get('MY_CUSTOM')['value'], 'hello');
  });

  test('allowlisted secret-looking name stays refused', () {
    values[JsEnvPolicy.allowlistKey] = 'JIRA_API_TOKEN';
    values['JIRA_API_TOKEN'] = 'REAL-SECRET';
    expect(tools.envGet('JIRA_API_TOKEN'), isNot(contains('REAL-SECRET')));
    expect(get('JIRA_API_TOKEN').containsKey('error'), isTrue);
  });

  test(
      'worst case: every declared credential is never answered, '
      'even when allowlisted', () {
    final secrets = PropertyNames.all.where(JsEnvPolicy.looksSecret).toList();
    expect(secrets, isNotEmpty);
    final secretValues = {for (final s in secrets) s: 'SECRET-$s-VALUE'};
    values.addAll(secretValues);
    values[JsEnvPolicy.allowlistKey] = secrets.join(',');
    final sweep = StringBuffer();
    for (final s in secrets) {
      sweep.write(tools.envGet(s));
    }
    sweep.write(tools.envList());
    for (final value in secretValues.values) {
      expect(sweep.toString(), isNot(contains(value)));
    }
  });

  test('env_list returns names only, never values', () {
    values['ADO_PROJECT'] = 'VALUE-SHOULD-NOT-LEAK';
    values['JIRA_API_TOKEN'] = 'TOKEN-SHOULD-NOT-LEAK';
    values[JsEnvPolicy.allowlistKey] = 'MY_CUSTOM,JIRA_API_TOKEN';
    final out = tools.envList();
    expect(out, isNot(contains('VALUE-SHOULD-NOT-LEAK')));
    expect(out, isNot(contains('TOKEN-SHOULD-NOT-LEAK')));
    final json = jsonDecode(out) as Map<String, dynamic>;
    final names = (json['names'] as List).cast<String>();
    expect(names, contains('ADO_PROJECT'));
    expect(names, contains('MY_CUSTOM'));
    expect(names, isNot(contains('JIRA_API_TOKEN')));
    expect(json['ignoredSecretLikeNames'], ['JIRA_API_TOKEN']);
  });

  test('env_list omits ignoredSecretLikeNames when nothing was rejected', () {
    final json = jsonDecode(tools.envList()) as Map<String, dynamic>;
    expect(json.containsKey('ignoredSecretLikeNames'), isFalse);
  });

  test('catalog exposes env_get and env_list in the env integration', () {
    final defs = envTools();
    expect(defs.map((d) => d.name), ['env_get', 'env_list']);
    expect(defs.every((d) => d.integration == 'env'), isTrue);
    expect(tools.handlers.keys, ['env_get', 'env_list']);
  });

  test('handlers dispatch through the same contract', () {
    values['ADO_PROJECT'] = 'PROJ';
    final out = tools.handlers['env_get']!({'name': 'ADO_PROJECT'});
    expect(jsonDecode(out)['value'], 'PROJ');
    expect(jsonDecode(tools.handlers['env_list']!({}))['names'], isNotEmpty);
  });
}
