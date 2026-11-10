import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'features/feed/tiktok_feed_screen.dart';
import 'features/feed/persistent_fullscreen_provider.dart';
import 'features/search/video_search_screen.dart';
import 'features/player/video_ui_provider.dart';
import 'features/security/biometric_gate.dart';
import 'features/feed/hashtag_feed_screen.dart';
import 'features/subscriptions/subscription_list_screen.dart';
import 'features/profile/user_details_screen.dart';
import 'features/profile/user_media_feed_screen.dart';
import 'core/navigation/navigation_provider.dart';
import 'core/client/background_sync.dart';
import 'core/client/transaction_id_service.dart';
import 'core/client/twitter_client.dart';
import 'features/settings/settings_provider.dart';
import 'core/client/twitter_account.dart';
import 'core/database/repository.dart';
import 'core/utils/lifecycle_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Honor device orientation: portrait or either landscape direction.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await Future.wait([
    TwitterAccount.init(),
    Repository.database,
  ]);

  runApp(const ProviderScope(child: XFlowApp()));
}

class XFlowApp extends ConsumerWidget {
  const XFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen to lifecycle changes
    ref.listen(lifecycleProvider, (previous, next) {
      if (next == AppLifecycle.resumed) {
        debugPrint('XFLOW: App resumed. Ensuring BackgroundSync is active.');
        TwitterClient.resetQueue();
        BackgroundSync.restart(TwitterClient(), ref.read(settingsProvider));
      }
    });

    ref.listen(settingsProvider, (prev, next) {
      if (prev?.syncInterval != next.syncInterval ||
          prev?.syncBatchSize != next.syncBatchSize ||
          prev?.pruneThreshold != next.pruneThreshold) {
        BackgroundSync.restart(TwitterClient(), next);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundSync.start(TwitterClient(), ref.read(settingsProvider));
    });

    return MaterialApp(
      title: 'Twitter vidéo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF70F0CE),
          brightness: Brightness.dark,
          surface: const Color(0xFF070809),
        ),
        scaffoldBackgroundColor: const Color(0xFF070809),
        appBarTheme: const AppBarTheme(
          backgroundColor: const Color(0xFF070809),
          elevation: 0,
          centerTitle: true,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xF20D1012),
          indicatorColor: const Color(0xFF70F0CE).withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      home: const BiometricGate(child: MainScaffold()),
    );
  }
}

class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    ref.listen(navigationProvider, (previous, next) {
      if (previous?.currentTab == MainTab.media &&
          next.currentTab != MainTab.media) {
        ref.read(persistentFullscreenProvider.notifier).setActive(false);
      }
    });
    final videoUiHidden = ref.watch(videoUiHiddenProvider);
    final persistentFullscreen = ref.watch(persistentFullscreenProvider);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final navNotifier = ref.read(navigationProvider.notifier);

    final mainScreens = IndexedStack(
      index: nav.currentTab.index,
      children: const [
        TiktokFeedScreen(),
        SubscriptionListScreen(isStandalone: false),
        HashtagListScreen(),
      ],
    );

    Widget? overlayScreen;
    if (nav.isVideoSearchOpen) {
      overlayScreen = const VideoSearchScreen();
    } else if (nav.selectedHashtag != null) {
      overlayScreen = HashtagMediaFeedScreen(hashtag: nav.selectedHashtag!);
    } else if (nav.selectedUser != null) {
      if (nav.userMediaInitialIndex != null) {
        overlayScreen = UserMediaFeedScreen(
          screenName: nav.selectedUser!,
          initialIndex: nav.userMediaInitialIndex!,
          initialTweetId: nav.userMediaInitialTweetId,
        );
      } else {
        overlayScreen = UserDetailsScreen(screenName: nav.selectedUser!);
      }
    }

    final body = Stack(
      children: [
        Visibility(
          visible: overlayScreen == null,
          maintainState: true,
          child: mainScreens,
        ),
        const Positioned(
          left: 0,
          top: 0,
          child: TransactionIdWebViewHost(),
        ),
        if (overlayScreen != null)
          Container(
            color: Colors.black,
            child: overlayScreen,
          ),
      ],
    );

    return PopScope(
      canPop: !persistentFullscreen && !nav.isVideoSearchOpen &&
          nav.selectedUser == null && nav.selectedHashtag == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (persistentFullscreen) {
          ref.read(persistentFullscreenProvider.notifier).setActive(false);
        } else {
          navNotifier.back();
        }
      },
      child: Scaffold(
        extendBody: false,
        body: body,
        bottomNavigationBar: nav.isVideoSearchOpen ||
                (persistentFullscreen && nav.currentTab == MainTab.media) ||
                (landscape && nav.currentTab == MainTab.media) ||
                (videoUiHidden && nav.currentTab == MainTab.media)
            ? null
            : NavigationBar(
          selectedIndex: nav.currentTab.index,
          onDestinationSelected: (index) {
            navNotifier.setTab(MainTab.values[index]);
            if (index == 1) {
              ref.invalidate(subscriptionListProvider);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library, color: Color(0xFF70F0CE)),
              label: 'Vidéos',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people, color: Color(0xFF70F0CE)),
              label: 'Abonnements',
            ),
            NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              selectedIcon: Icon(Icons.trending_up, color: Color(0xFF70F0CE)),
              label: 'Hashtags',
            ),
          ],
        ),
      ),
    );
  }
}
