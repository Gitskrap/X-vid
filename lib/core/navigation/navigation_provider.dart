import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MainTab { media, subscriptions, trending }

class NavigationState {
  final MainTab currentTab;
  final String? selectedUser; // If not null, show UserDetails or UserMediaFeed
  final int? userMediaInitialIndex;
  final String? userMediaInitialTweetId;
  final String? selectedHashtag;
  final bool isVideoSearchOpen;

  NavigationState({
    this.currentTab = MainTab.media,
    this.selectedUser,
    this.userMediaInitialIndex,
    this.userMediaInitialTweetId,
    this.selectedHashtag,
    this.isVideoSearchOpen = false,
  });

  NavigationState copyWith({
    MainTab? currentTab,
    String? selectedUser,
    int? userMediaInitialIndex,
    String? userMediaInitialTweetId,
    String? selectedHashtag,
    bool clearUser = false,
    bool clearMediaIndex = false,
    bool clearHashtag = false,
    bool? isVideoSearchOpen,
  }) {
    return NavigationState(
      currentTab: currentTab ?? this.currentTab,
      selectedUser: clearUser ? null : (selectedUser ?? this.selectedUser),
      userMediaInitialIndex: (clearUser || clearMediaIndex)
          ? null
          : (userMediaInitialIndex ?? this.userMediaInitialIndex),
      userMediaInitialTweetId: (clearUser || clearMediaIndex)
          ? null
          : (userMediaInitialTweetId ?? this.userMediaInitialTweetId),
      selectedHashtag: (clearHashtag || clearUser)
          ? null
          : (selectedHashtag ?? this.selectedHashtag),
      isVideoSearchOpen: isVideoSearchOpen ?? this.isVideoSearchOpen,
    );
  }
}

class NavigationNotifier extends Notifier<NavigationState> {
  @override
  NavigationState build() => NavigationState();

  void setTab(MainTab tab) {
    state =
        state.copyWith(currentTab: tab, clearUser: true, clearHashtag: true, isVideoSearchOpen: false);
  }

  void selectUser(String screenName) {
    state = state.copyWith(
        selectedUser: screenName, clearMediaIndex: true, clearHashtag: true, isVideoSearchOpen: false);
  }

  void openUserMedia(String screenName, int index, {String? tweetId}) {
    state = state.copyWith(
        selectedUser: screenName,
        userMediaInitialIndex: index,
        userMediaInitialTweetId: tweetId,
        clearHashtag: true, isVideoSearchOpen: false);
  }

  void selectHashtag(String hashtag) {
    state = state.copyWith(selectedHashtag: hashtag, isVideoSearchOpen: false);
  }

  void openVideoSearch() {
    state = state.copyWith(clearUser: true, clearHashtag: true, isVideoSearchOpen: true);
  }

  void back() {
    if (state.isVideoSearchOpen) {
      state = state.copyWith(isVideoSearchOpen: false);
    } else if (state.selectedHashtag != null) {
      state = state.copyWith(clearHashtag: true);
    } else if (state.userMediaInitialIndex != null) {
      state = state.copyWith(clearMediaIndex: true);
    } else if (state.selectedUser != null) {
      state = state.copyWith(clearUser: true);
    }
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationState>(
  NavigationNotifier.new,
);
