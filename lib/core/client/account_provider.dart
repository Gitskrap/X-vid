import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'twitter_account.dart';
import '../database/entities.dart';
import '../database/repository.dart';

class AccountNotifier extends Notifier<Account?> {
  @override
  Account? build() {
    return TwitterAccount.currentAccount;
  }

  Future<void> logout({Account? account}) async {
    await TwitterAccount.logout(account: account);
    state = TwitterAccount.currentAccount;
    ref.invalidate(savedAccountsProvider);
  }

  Future<void> login(Account account) async {
    await TwitterAccount.setCurrentAccount(account);
    state = account;
    ref.invalidate(savedAccountsProvider);
  }
}

final accountProvider = NotifierProvider<AccountNotifier, Account?>(
  AccountNotifier.new,
);

/// Saved X accounts. Only one account is active for API requests at a time.
final savedAccountsProvider = FutureProvider<List<Account>>(
  (ref) => Repository.getAccounts(),
);
