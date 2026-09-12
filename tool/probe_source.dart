import 'package:dmtools/src/agents/github_ticket_source.dart';

Future<void> main() async {
  try {
    final t = await GithubIssueSource()
        .fetch('repo:epam/dmtools-dart is:issue is:open -label:bug');
    print(
        'OK tickets=${t.length} first=${t.isNotEmpty ? t.first['key'] : '-'}');
  } catch (e) {
    print('FAIL: $e');
  }
}
