import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/entities.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/features/subscriptions/subscription_list_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    final db = await Repository.database;
    await db.delete(tableSubscriptions);
  });

  test('new subscription is visible immediately despite previous search',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(subscriptionListProvider.notifier);
    await notifier.refresh();
    notifier.setSearchQuery('unrelated search');
    expect(container.read(subscriptionListProvider).filteredSubscriptions,
        isEmpty);

    final added = await notifier.saveSubscription(
      Subscription(id: 'test_nasa', name: 'NASA',
          screenName: 'NASA'),
    );
    expect(added, isTrue);
    final updated = container.read(subscriptionListProvider);
    expect(updated.isLoading, false);
    expect(updated.searchQuery, '');
    expect(updated.allSubscriptions, hasLength(1));
    expect(updated.filteredSubscriptions.single.screenName, 'NASA');

    final persisted = await Repository.getSubscriptions();
    expect(persisted.single.screenName, 'NASA');
  });

  test('a second add is blocked and the visible list stays unchanged',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(subscriptionListProvider.notifier);
    await notifier.refresh();

    final account = Subscription(
        id: 'test_repeat', name: 'Example', screenName: 'Example');
    expect(await notifier.saveSubscription(account), isTrue);
    notifier.setSearchQuery('different');
    expect(await notifier.saveSubscription(account), isFalse);
    expect(container.read(subscriptionListProvider).allSubscriptions,
        hasLength(1));
  });
}
