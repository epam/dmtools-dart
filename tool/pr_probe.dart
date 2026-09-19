import 'package:dmtools/src/config/property_reader.dart';

void main() {
  final t = PropertyReader().getValue('SOURCE_GITHUB_TOKEN');
  print('len=${t?.length} sha=${t.hashCode}');
}
