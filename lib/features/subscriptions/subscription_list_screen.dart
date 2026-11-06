import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/database/repository.dart';
import '../../core/database/entities.dart';
import '../../core/utils/media_cache_manager.dart';
import '../../core/utils/app_logger.dart';
import '../profile/user_details_screen.dart';
import '../../core/navigation/navigation_provider.dart';
import '../settings/settings_screen.dart';
import 'subscription_handle.dart';
import 'account_discovery_screen.dart';
import '../../core/client/public_x_client.dart';
import 'dart:async';

enum SubscriptionSort {
  name,
  handle,
  followers,
  views,
}

class SubscriptionListState {
  final List<Subscription> allSubscriptions;
  final Map<String, int> userViews;
  final String searchQuery;
  final SubscriptionSort sort;
  final bool isAscending;
  final bool isLoading;

  SubscriptionListState({
    this.allSubscriptions = const [],
    this.userViews = const {},
    this.searchQuery = '',
    this.sort = SubscriptionSort.name,
    this.isAscending = true,
    this.isLoading = true,
  });

  List<Subscription> get filteredSubscriptions {
    List<Subscription> filtered = List.from(allSubscriptions);
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((sub) {
        return sub.name.toLowerCase().contains(query) ||
            sub.screenName.toLowerCase().contains(query);
      }).toList();
    }

    int multiplier = isAscending ? 1 : -1;

    switch (sort) {
      case SubscriptionSort.name:
        filtered.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()) * multiplier);
        break;
      case SubscriptionSort.handle:
        filtered.sort((a, b) =>
            a.screenName.toLowerCase().compareTo(b.screenName.toLowerCase()) *
            multiplier);
        break;
      case SubscriptionSort.followers:
        filtered.sort((a, b) =>
            (a.followersCount ?? 0).compareTo(b.followersCount ?? 0) *
            multiplier);
        break;
      case SubscriptionSort.views:
        filtered.sort((a, b) {
          final viewsA = userViews[a.screenName.toLowerCase()] ?? 0;
          final viewsB = userViews[b.screenName.toLowerCase()] ?? 0;
          return viewsA.compareTo(viewsB) * multiplier;
        });
        break;
    }
    return filtered;
  }

  bool isSubscribed(String screenName) {
    final normalized =
        screenName.startsWith('@') ? screenName.substring(1) : screenName;
    final lower = normalized.toLowerCase();
    return allSubscriptions
        .any((sub) => sub.screenName.toLowerCase() == lower);
  }

  SubscriptionListState copyWith({
    List<Subscription>? allSubscriptions,
    Map<String, int>? userViews,
    String? searchQuery,
    SubscriptionSort? sort,
    bool? isAscending,
    bool? isLoading,
  }) {
    return SubscriptionListState(
      allSubscriptions: allSubscriptions ?? this.allSubscriptions,
      userViews: userViews ?? this.userViews,
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      isAscending: isAscending ?? this.isAscending,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SubscriptionListNotifier extends Notifier<SubscriptionListState> {
  int _loadVersion = 0;

  @override
  SubscriptionListState build() {
    _load();
    return SubscriptionListState();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final subscriptions = await Repository.getSubscriptions();
      Map<String, int> views = {};
      try {
        views = await Repository.getPlayedCountsByUser();
      } catch (error) {
        AppLogger.log('Could not load per-account view counts: $error');
      }
      if (!ref.mounted || version != _loadVersion) return;
      state = state.copyWith(
        allSubscriptions: subscriptions,
        userViews: views,
        isLoading: false,
      );
    } catch (error) {
      AppLogger.log('Could not load local subscriptions: $error');
      if (ref.mounted && version == _loadVersion) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSort(SubscriptionSort sort) {
    state = state.copyWith(sort: sort);
  }

  void toggleOrder() {
    state = state.copyWith(isAscending: !state.isAscending);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  /// Save the public handle locally, without any X credentials or network
  /// request. This does not follow the account on X itself.
  Future<bool> addHandle(String value) async {
    final handle = normalizeSubscriptionHandle(value);
    if (handle == null) {
      throw const FormatException(
        'Indique un @identifiant (1 à 15 caractères) '
        'ou un lien de profil x.com.',
      );
    }
    final result = await saveSubscription(Subscription(
      id: 'local_' + handle.toLowerCase(),
      screenName: handle,
      name: handle,
    ));
    if (result) {
      // Local save completes first, even if the public API is unreachable.
      unawaited(_enrichSavedHandle(handle));
    }
    return result;
  }

  Future<bool> saveSubscription(Subscription sub) async {
    if (isSubscribed(sub.screenName)) return false;
    // Persist before acknowledging success, then publish a fresh list
    // immediately. A background refresh must not replace it with a stale
    // snapshot. Clear the local search that otherwise hides the new account.
    await Repository.insertSubscription(sub);
    _loadVersion++;
    state = state.copyWith(
      allSubscriptions: [...state.allSubscriptions, sub],
      searchQuery: '',
      isLoading: false,
    );
    return true;
  }

  Future<void> _enrichSavedHandle(String handle) async {
    try {
      final profile = await PublicXClient().profile(handle);
      if (profile == null || !ref.mounted ||
          !isSubscribed(handle)) return;
      // The same screen name may have been removed while the request ran.
      final database = await Repository.database;
      final existing = await database.query(tableSubscriptions,
        where: 'LOWER(screen_name) = ?',
        whereArgs: [handle.toLowerCase()],
        limit: 1,
      );
      if (existing.isEmpty) return;
      final old = Subscription.fromMap(existing.first);
      await database.update(tableSubscriptions,
        {
          'name': profile.name,
          'profile_image_url': profile.profileImageUrl,
          'description': profile.description,
          'followers_count': profile.followersCount,
          'following_count': profile.followingCount,
        },
        where: 'id = ?',
        whereArgs: [old.id],
      );
      if (ref.mounted) {
        state = state.copyWith(
          allSubscriptions: [
            for (final sub in state.allSubscriptions)
              if (sub.screenName.toLowerCase() == handle.toLowerCase())
                Subscription(
                  id: sub.id,
                  screenName: sub.screenName,
                  name: profile.name,
                  profileImageUrl: profile.profileImageUrl,
                  description: profile.description,
                  followersCount: profile.followersCount,
                  followingCount: profile.followingCount,
                )
              else
                sub,
          ],
        );
      }
    } catch (error) {
      AppLogger.log('Optional public profile enrichment unavailable: $error');
    }
  }

  Future<void> toggleSubscription(Subscription sub) async {
    final exists = isSubscribed(sub.screenName);

    // Optimistic update for immediate UI feedback
    final currentSubs = List<Subscription>.from(state.allSubscriptions);
    if (exists) {
      currentSubs.removeWhere(
          (s) => s.screenName.toLowerCase() == sub.screenName.toLowerCase());
    } else {
      currentSubs.add(sub);
    }
    state = state.copyWith(allSubscriptions: currentSubs);

    try {
      if (exists) {
        final db = await Repository.database;
        await db.delete('subscriptions',
            where: 'LOWER(screen_name) = ?',
            whereArgs: [sub.screenName.toLowerCase()]);
      } else {
        await Repository.insertSubscription(sub);
      }
    } catch (e) {
      AppLogger.log('XFLOW: Error toggling subscription: $e');
      // Rollback on error
      await _load();
      return;
    }

    // Refresh to ensure everything (including views) is in sync
    await _load();
  }

  bool isSubscribed(String screenName) {
    return state.isSubscribed(screenName);
  }
}

final subscriptionListProvider =
    NotifierProvider<SubscriptionListNotifier, SubscriptionListState>(
  SubscriptionListNotifier.new,
);

class SubscriptionListScreen extends ConsumerWidget {
  final bool isStandalone;

  const SubscriptionListScreen({super.key, this.isStandalone = true});

  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final text = TextEditingController();
    String? errorMessage;
    bool submitting = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) {
            Future<void> save() async {
              if (submitting) return;
              updateDialog(() {
                submitting = true;
                errorMessage = null;
              });
              try {
                final added = await ref.read(subscriptionListProvider.notifier)
                    .addHandle(text.text);
                if (!dialogContext.mounted) return;
                if (!added) {
                  updateDialog(() {
                    submitting = false;
                    errorMessage = 'Ce compte est déjà dans ta liste.';
                  });
                  return;
                }
                Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Compte enregistré localement.')),
                  );
                }
              } on FormatException catch (error) {
                if (dialogContext.mounted) {
                  updateDialog(() {
                    submitting = false;
                    errorMessage = error.message;
                  });
                }
              } catch (_) {
                if (dialogContext.mounted) {
                  updateDialog(() {
                    submitting = false;
                    errorMessage = 'Enregistrement impossible.';
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Ajouter un compte X'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enregistre un compte public sans te connecter à X.'),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    controller: text,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Identifiant ou lien X',
                      hintText: '@NASA',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => save(),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(errorMessage!,
                        style: const TextStyle(color: Colors.orangeAccent)),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'La liste fonctionne hors connexion X. '
                    'L’accès aux nouvelles vidéos dépend toujours de X.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: submitting ? null : save,
                  child: const Text('Ajouter'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      text.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionListProvider);
    final subs = state.filteredSubscriptions;

    // Keep the app bar and Add/Search actions available even if the local
    // database is still loading or its optional view counts failed.
    Widget content = state.isLoading
        ? const Center(child: CircularProgressIndicator())
        : subs.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.searchQuery.isEmpty
                      ? 'Aucun compte enregistré. Ajoute un @compte sans '
                        'connecter ton compte X.'
                      : 'Aucun compte correspondant à la recherche.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountDiscoveryScreen(
                        initialQuery: state.searchQuery,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Rechercher des comptes publics'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addAccount(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Ajouter un @identifiant'),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              final views = state.userViews[sub.screenName.toLowerCase()] ?? 0;

              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: sub.profileImageUrl != null
                        ? CachedNetworkImageProvider(
                            sub.profileImageUrl!,
                            cacheManager: CustomMediaCacheManager.getInstance(),
                          )
                        : null,
                    child: sub.profileImageUrl == null
                        ? const Icon(Icons.person, size: 24)
                        : null,
                  ),
                  title: Text(
                    sub.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '@${sub.screenName}${sub.followersCount != null ? " • ${_formatCount(sub.followersCount!)} followers" : ""}${views > 0 ? " • $views views" : ""}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  trailing: IconButton(
                    tooltip: 'Retirer de ma liste',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Retirer le compte ?'),
                          content: Text(
                            'Retirer @' + sub.screenName +
                            ' de ta liste locale ? Cela ne change '
                            'rien à ton compte X.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Retirer'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref.read(subscriptionListProvider.notifier)
                            .toggleSubscription(sub);
                      }
                    },
                  ),
                  onTap: () {
                    if (isStandalone) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserDetailsScreen(screenName: sub.screenName),
                        ),
                      );
                    } else {
                      ref
                          .read(navigationProvider.notifier)
                          .selectUser(sub.screenName);
                    }
                  },
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        leading: isStandalone
            ? null
            : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(subscriptionListProvider.notifier).refresh(),
              ),
        title: const Text('Abonnements'),
        actions: [
          IconButton(
            tooltip: 'Rechercher des comptes publics sans connexion X',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountDiscoveryScreen(
                  initialQuery: state.searchQuery,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ajouter un compte sans connexion',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _addAccount(context, ref),
          ),
          if (!isStandalone)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const SettingsScreen()),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: _buildSearchAndSort(context, ref),
        ),
      ),
      body: content,
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildSearchAndSort(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          const _SubscriptionsSearchBar(),
          const SizedBox(height: 8),
          const SubscriptionSortSettings(),
        ],
      ),
    );
  }
}

/// The local search text and Riverpod filter must stay synchronized. Adding
/// an account clears the filter, even while the discovery route is on top.
class _SubscriptionsSearchBar extends ConsumerStatefulWidget {
  const _SubscriptionsSearchBar();

  @override
  ConsumerState<_SubscriptionsSearchBar> createState() =>
      _SubscriptionsSearchBarState();
}

class _SubscriptionsSearchBarState
    extends ConsumerState<_SubscriptionsSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(subscriptionListProvider).searchQuery,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _discover(BuildContext context, String query) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountDiscoveryScreen(initialQuery: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      subscriptionListProvider.select((state) => state.searchQuery),
      (previous, next) {
        if (_controller.text == next) return;
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );

    return SearchBar(
      controller: _controller,
      hintText: 'Mes abonnements ou recherche publique...',
      onChanged: ref.read(subscriptionListProvider.notifier).setSearchQuery,
      onSubmitted: (query) => _discover(context, query),
      leading: const Icon(Icons.search),
      trailing: [
        IconButton(
          tooltip: 'Rechercher des comptes publics',
          icon: const Icon(Icons.travel_explore),
          onPressed: () => _discover(context, _controller.text),
        ),
      ],
      elevation: WidgetStateProperty.all(0),
      backgroundColor: WidgetStateProperty.all(
        Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

class SubscriptionSortSettings extends ConsumerWidget {
  const SubscriptionSortSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionListProvider);
    final notifier = ref.read(subscriptionListProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SortChip(
            label: 'Nom',
            isSelected: state.sort == SubscriptionSort.name,
            onTap: () => notifier.setSort(SubscriptionSort.name),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: 'Identifiant',
            isSelected: state.sort == SubscriptionSort.handle,
            onTap: () => notifier.setSort(SubscriptionSort.handle),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: 'Abonnés',
            isSelected: state.sort == SubscriptionSort.followers,
            onTap: () => notifier.setSort(SubscriptionSort.followers),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: 'Vues',
            isSelected: state.sort == SubscriptionSort.views,
            onTap: () => notifier.setSort(SubscriptionSort.views),
          ),
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: Icon(
              state.isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            onPressed: notifier.toggleOrder,
            tooltip: state.isAscending ? 'Ascending' : 'Descending',
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      showCheckmark: false,
    );
  }
}
