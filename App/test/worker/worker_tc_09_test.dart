import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-09: Robustly parses isVerified across boolean, string, and integer formats', () {
    // True boolean
    expect(WorkerModel.fromJson({'id': 1, 'isVerified': true}).isVerified, isTrue);

    // True PascalCase
    expect(WorkerModel.fromJson({'id': 2, 'IsVerified': true}).isVerified, isTrue);

    // String "true"
    expect(WorkerModel.fromJson({'id': 3, 'is_verified': 'true'}).isVerified, isTrue);

    // Integer 1
    expect(WorkerModel.fromJson({'id': 4, 'isVerified': 1}).isVerified, isTrue);

    // False / absent
    expect(WorkerModel.fromJson({'id': 5, 'isVerified': false}).isVerified, isFalse);
    expect(WorkerModel.fromJson({'id': 6}).isVerified, isFalse);
  });
}
