import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/client/public_x_client.dart';
import '../../core/database/entities.dart';
import '../../core/utils/media_cache_manager.dart';
import '../../core/navigation/navigation_provider.dart';
import 'subscription_handle.dart';
import 'subscription_list_screen.dart';

/// Global discovery for public X profiles, independent of user X auth.
/// The query is sent to the FxEmbed public API; credentials are never sent.
class AccountDiscoveryScreen extends ConsumerStatefulWidget {
  final String initialQuery;
  const AccountDiscoveryScreen({super.key, this.initialQuery = ''});

  @override
  ConsumerState<AccountDiscoveryScreen> createState() =>
      _AccountDiscoveryScreenState();
}

class _AccountDiscoveryScreenState
    extends ConsumerState<AccountDiscoveryScreen> {
  final _controller = TextEditingController();
  final _client = PublicXClient();
  Timer? _debounce;
  int _searchToken = 0;
  List<Subscription> _results = [];
  bool _loading = false;
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (_controller.text.trim().length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchToken++;
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _searchToken++;
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 450),
      _search,
    );
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.length < 2) return;
    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _client.searchAccounts(query);
      if (!mounted || token != _searchToken) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = [];
        _error = 'La recherche publique est indisponible. '
            'Tu peux toujours enregistrer directement un @identifiant.';
      });
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addProfile(Subscription profile) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final added = await ref
          .read(subscriptionListProvider.notifier)
          .saveSubscription(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added
              ? 'Compte @' + profile.screenName + ' enregistré.'
              : 'Ce compte figure déjà dans tes abonnements.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistrement local impossible.')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addTypedHandle() async {
    if (_adding) return;
    final handle = normalizeSubscriptionHandle(_controller.text);
    if (handle == null) return;
    setState(() => _adding = true);
    try {
      final added =
          await ref.read(subscriptionListProvider.notifier).addHandle(handle);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added
              ? 'Compte @' + handle + ' enregistré, sans connexion X.'
              : '@' + handle + ' est déjà dans ta liste.'),
        ),
      );
      if (added) {
        // Return to the now-updated subscriptions list automatically.
        Navigator.of(context).pop();
      }
    } on FormatException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifiant X invalide.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistrement impossible.')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(subscriptionListProvider);
    final manualHandle = normalizeSubscriptionHandle(_controller.text);
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher un compte X')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (text) {
                setState(() {});
                _onQueryChanged(text);
              },
              decoration: InputDecoration(
                hintText: 'Nom, @compte ou mots-clés',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Lancer la recherche de comptes',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (manualHandle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _adding ? null : _addTypedHandle,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text('Enregistrer @' + manualHandle +
                      ' sans connexion X'),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Text(
              'Recherche des comptes publics via FxEmbed, sans utiliser '
              'ton compte X. La recherche peut être limitée par ce service.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _loading
                          ? 'Recherche des comptes publics…'
                          : hasQuery && _error == null
                              ? 'Aucune suggestion disponible. '
                                  'Tu peux enregistrer un @identifiant '
                                  'directement ci-dessus.'
                              : 'Recherche par nom ou identifiant, '
                                  'même sans compte X.',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      final registered = saved.isSubscribed(user.screenName);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user.profileImageUrl != null
                              ? CachedNetworkImageProvider(
                                  user.profileImageUrl!,
                                  cacheManager:
                                      CustomMediaCacheManager.getInstance(),
                                )
                              : null,
                          child: user.profileImageUrl == null
                              ? const Icon(Icons.person_outline)
                              : null,
                        ),
                        title: Text(user.name),
                        subtitle: Text('@' + user.screenName),
                        onTap: () async {
                          if (!registered) {
                            await _addProfile(user);
                          }
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          ref.read(navigationProvider.notifier)
                              .selectUser(user.screenName);
                        },
                        trailing: IconButton(
                          tooltip: registered
                              ? 'Déjà dans mes abonnements'
                              : 'Ajouter à mes abonnements locaux',
                          onPressed: registered || _adding
                              ? null
                              : () async {
                                  await _addProfile(user);
                                  if (!context.mounted) return;
                                  if (ref.read(subscriptionListProvider)
                                      .isSubscribed(user.screenName)) {
                                    // The local list is updated before pop.
                                    Navigator.of(context).pop();
                                  }
                                },
                          icon: Icon(registered
                              ? Icons.check_circle
                              : Icons.person_add_alt_1),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
