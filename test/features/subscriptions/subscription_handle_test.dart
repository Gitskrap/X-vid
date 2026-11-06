import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/subscriptions/subscription_handle.dart';

void main() {
  test('local handles, @names and profile links are supported without login',
      () {
    expect(normalizeSubscriptionHandle('@NASA'), 'NASA');
    expect(normalizeSubscriptionHandle(' paris '), 'paris');
    expect(normalizeSubscriptionHandle('https://x.com/NASA'), 'NASA');
    expect(normalizeSubscriptionHandle('https://twitter.com/FranceTV/'),
        'FranceTV');
    expect(normalizeSubscriptionHandle('www.x.com/example_01'), 'example_01');
  });

  test('invalid handles and tweet links are rejected', () {
    expect(normalizeSubscriptionHandle(''), isNull);
    expect(normalizeSubscriptionHandle('paris football'), isNull);
    expect(normalizeSubscriptionHandle('https://x.com/NASA/status/123'), isNull);
    expect(normalizeSubscriptionHandle('https://evil.com/NASA'), isNull);
    expect(normalizeSubscriptionHandle('https://x.com.evil.com/NASA'), isNull);
    expect(normalizeSubscriptionHandle('long_user_name_more_than_15'), isNull);
  });
}
