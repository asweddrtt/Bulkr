import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/analytics_events.dart';
import '../core/ad_moment.dart';
import '../core/deep_link.dart';
import '../core/telemetry.dart';
import '../cubit/conversations/conversations_cubit.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../cubit/feed/feed_cubit.dart';
import '../cubit/notifications/notifications_cubit.dart';
import '../data/ads_service.dart';
import '../data/deep_link_listener.dart';
import '../data/chat_repository.dart';
import '../data/push_service.dart';
import '../models/conversation.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../cubit/tracker/tracker_cubit.dart';
import '../widgets/bulkr_nav_bar.dart';
import 'feed_screen.dart';
import 'meals_screen.dart';
import 'profile_screen.dart';
import 'tracker_screen.dart';
import 'dashboard_screen.dart';
import 'chat_screen.dart';
import 'conversations_screen.dart';
import 'post_screen.dart';
import 'notifications_screen.dart';

/// Post-onboarding shell: bottom navigation over the main sections.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// The five tabs, in order.
  ///
  /// Public so a test can check that every label is a key the translations
  /// actually carry. Four of these used to be the English word itself, which
  /// easy_localization renders by handing back the key it could not find — so
  /// the bar read correctly in English and read English in every other locale,
  /// silently, with nothing to notice unless you switched language.
  static const List<NavDestination> destinations = [
    NavDestination(Icons.dashboard_sharp, 'nav_dashboard'),
    NavDestination(Icons.restaurant_sharp, 'nav_meals'),
    NavDestination(Icons.dynamic_feed_sharp, 'nav_feed'),
    NavDestination(Icons.electric_bolt_sharp, 'nav_tracker'),
    NavDestination(Icons.person_sharp, 'nav_profile'),
  ];

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 2;

  StreamSubscription<PushTap>? _taps;

  /// Links from outside the app — a shared post, tapped in a message.
  ///
  /// Owned by the shell for the same reason `_taps` is: both need a navigator,
  /// and this is the first widget in the tree that has one and outlives every
  /// tab.
  final DeepLinkListener _deepLinks = DeepLinkListener();

  /// When the app last went into the background.
  ///
  /// Null until it has, so the first resume of a launch — which on iOS
  /// sometimes fires without a preceding pause — cannot be read as a return
  /// from four hours away.
  DateTime? _leftAt;

  /// False until the shell has drawn once. See [_openFromPush].
  bool _shellIsWarm = false;

  /// Whether the nav bar is drawn small.
  ///
  /// Driven by scroll direction rather than position: what matters is that the
  /// user is reading downwards, not how far down they have got.
  bool _navCompact = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Asked for here rather than at launch. A notification permission prompt
    // on first open, before anyone has seen what the app is, is the one most
    // reliably denied — and on iOS a denial is close to permanent, since the
    // app cannot ask a second time.
    final PushService push = context.read<PushService>();
    push.signIn();

    // A notification that opens the app and then drops you on whatever tab you
    // last used is a notification that wasted the tap. Two sources: one for a
    // tap while the app was in the background, one for a tap that launched it
    // from cold.
    _taps = push.taps.listen(_openFromPush);
    push.takeInitialTap().then((PushTap? tap) {
      if (tap != null) _openFromPush(tap);
    });

    // Anything arriving after this first frame reached an app that was
    // already open. Set in a post-frame callback rather than at the end of
    // `initState`, because the cold-start tap resolves asynchronously and
    // would otherwise race this flag.
    WidgetsBinding.instance.addPostFrameCallback((_) => _shellIsWarm = true);

    // The same two cases as the notification above: one for a link tapped
    // while the app is running, one for the link that launched it.
    _deepLinks.start(_openFromLink);
    _deepLinks.takeInitialLink().then((DeepLink? link) {
      if (link != null) _openFromLink(link);
    });

    // Fetched once when the shell mounts rather than on each tab switch, so
    // moving between tabs doesn't re-hit the network.
    context.read<ProfileCubit>().load();
    context.read<MealsCubit>().load();
    // Cache first, then the server — so a subscriber is not shown the ads they
    // paid to remove for the second it takes to ask. Called here as well as
    // where the cubit is created, because this is the point at which an
    // account is actually signed in: the provider runs once per process, and a
    // second account signing in on the same launch would otherwise inherit the
    // first one's answer.
    context.read<EntitlementCubit>().load();

    // Consent, the tracking prompt, then the SDK — started here rather than at
    // launch so that a new account goes through onboarding before it is shown
    // either prompt. Nothing waits on it; the first banner appearing a second
    // late is invisible.
    unawaited(context.read<AdsService>().start());
    context.read<FeedCubit>().load();
    context.read<TrackerCubit>().load();
  }

  @override
  void dispose() {
    unawaited(_deepLinks.dispose());
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Where a shared link lands.
  ///
  /// Never throws, for the same reason [_openFromPush] does not: this runs on
  /// a stream nobody awaits and on a future nobody catches, so an exception
  /// here would be an unhandled one on the launch path.
  Future<void> _openFromLink(DeepLink link) async {
    if (!mounted) return;

    try {
      switch (link) {
        case PostDeepLink(:final String postId):
          await PostScreen.open(context, postId, source: 'deep_link');
      }
    } catch (error, stackTrace) {
      debugPrint('Bulkr: could not open a link — $error');
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'opening a deep link'));
    }
  }

  /// Where a tapped notification lands.
  ///
  /// Never throws: this runs on a stream nobody awaits and on a future nobody
  /// catches, so an exception here would be an unhandled one — on the launch
  /// path, which is the worst place in the app to have one.
  Future<void> _openFromPush(PushTap tap) async {
    if (!mounted) return;

    unawaited(Telemetry.send(AnalyticsEvent.pushOpened(
      kind: tap.kind,
      // A tap that arrived through `takeInitialTap` launched the app; one off
      // the stream reached an app that was already running. The two say
      // different things about whether notifications are bringing people back.
      fromCold: !_shellIsWarm,
    )));

    try {
      if (!tap.isMessage) {
        await NotificationsScreen.open(context);
        return;
      }

      final String? conversationId = tap.conversationId;
      if (conversationId == null) {
        // A message with no thread on it. The inbox is still the right answer
        // — it is where the message is.
        await ConversationsScreen.open(context);
        return;
      }

      await _openThread(conversationId);
    } catch (error) {
      debugPrint('Bulkr: could not open a tapped notification — $error');
    }
  }

  /// Opens one thread, having worked out whose it is.
  ///
  /// The push carries a conversation id and nothing else, while the chat screen
  /// needs a name for its title. Rather than a new endpoint for one field, this
  /// reads the inbox the user already has and takes the row — one call, a list
  /// bounded by how many people they talk to, and it doubles as the check that
  /// the thread is still theirs to open.
  Future<void> _openThread(String conversationId) async {
    final ChatRepository chat = context.read<ChatRepository>();
    final ConversationsCubit conversations = context.read<ConversationsCubit>();
    final NavigatorState navigator = Navigator.of(context);

    final List<Conversation> threads = await chat.fetchConversations();
    if (!mounted) return;

    final Conversation? thread = threads
        .where((Conversation c) => c.id == conversationId)
        .firstOrNull;

    // Gone, or never theirs. The inbox rather than an error: by the time
    // somebody taps a notification the thread may have been deleted, and a
    // screen that says so is less use than the list of the ones that remain.
    if (thread == null) {
      await ConversationsScreen.open(context);
      return;
    }

    // Same as opening it from the inbox: zero the badge before the screen
    // rather than after, so the list behind it is not still counting what is
    // on screen.
    conversations.markSeen(thread.id);

    await ChatScreen.open(
      navigator: navigator,
      chat: chat,
      conversationId: thread.id,
      currentUserId: chat.currentUserId,
      title: thread.otherName.isEmpty
          ? 'chat_person_gone'.tr()
          : thread.otherName,
      otherId: thread.otherId,
      avatarUrl: thread.otherAvatarUrl,
    );

    await conversations.refresh();
  }

  /// Two things that go stale while the app is not being looked at.
  ///
  /// Coming back is the moment they matter and the moment nobody minds a
  /// request, so this is where they are caught rather than on a timer. A timer
  /// would be asking a server the same two questions all day for a user who is
  /// not there — the pattern that makes a small app expensive to run.
  ///
  /// Both are cheap and neither blanks anything: the unread count is one call
  /// that only moves a dot, and the tracker returns immediately unless the day
  /// has actually turned over.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    // Coming back after a real absence is a seam: nothing was interrupted,
    // because nothing was in progress. Four hours is the threshold, and it is
    // AdPolicy that enforces it — this only measures.
    final DateTime? left = _leftAt;
    if (left != null) {
      _leftAt = null;
      unawaited(AdMoment.of(context).returnedAfter(DateTime.now().difference(left)));
    }

    context.read<ConversationsCubit>().refresh();
    context.read<NotificationsCubit>().refreshBadge();
    context.read<TrackerCubit>().refreshIfDayChanged();
    // A subscription can start, renew or lapse while the app is closed, and
    // none of those reaches the phone — a renewal is between the store and the
    // backend. Coming back is when it is worth re-asking, and it is one row.
    context.read<EntitlementCubit>().refresh();
  }

  /// Index of the Tracker tab, which needs a nudge the others do not.
  static const int _trackerIndex = 3;

  /// Shrinks the bar while scrolling down, restores it on the way up.
  ///
  /// One listener on the shell rather than a controller per screen. Every tab
  /// scrolls its own list and two of them scroll horizontally as well, and a
  /// [UserScrollNotification] carries both the axis and the direction — so the
  /// shell can read the gesture without any screen having to report it.
  ///
  /// `UserScrollNotification` and not `ScrollUpdateNotification`: only the
  /// first is a person's finger. The second also fires for a
  /// `RefreshIndicator` settling, a programmatic `animateTo`, and the bounce at
  /// the end of a list — none of which are someone asking for more room.
  bool _onUserScroll(UserScrollNotification notification) {
    // The feed swipes between For You and Discover and Meals between its two
    // tabs. A sideways gesture is not a reading gesture.
    if (notification.metrics.axis != Axis.vertical) return false;

    // A list shorter than its viewport still reports scroll direction as the
    // overscroll bounces. Resizing the bar because somebody tugged at a list
    // with four items in it would make it flicker for no reason.
    if (!notification.metrics.hasContentDimensions ||
        notification.metrics.maxScrollExtent <= BulkrNavBar.barHeight) {
      return false;
    }

    switch (notification.direction) {
      // Content moving up the screen: reading onwards.
      case ScrollDirection.reverse:
        _setNavCompact(true);
      case ScrollDirection.forward:
        _setNavCompact(false);
      // Idle arrives at the end of every gesture. Leaving the bar as it is
      // means it stays small through a pause mid-scroll, and comes back the
      // moment the user heads back up.
      case ScrollDirection.idle:
        break;
    }

    return false;
  }

  void _setNavCompact(bool compact) {
    if (_navCompact == compact) return;
    setState(() => _navCompact = compact);
  }

  void _select(int index) {
    setState(() => _currentIndex = index);

    // A new tab is at the top of its own list and nobody has scrolled it, so
    // the bar goes back to full size.
    _setNavCompact(false);

    // Everything here lives in an IndexedStack, so each screen is built once
    // and kept alive — which is what makes switching tabs instant, and what
    // would otherwise let the tracker show yesterday's log under today's
    // heading after the app sat in the background overnight. The cubit does
    // nothing when the day has not turned over, so this is free.
    if (index == _trackerIndex) {
      context.read<TrackerCubit>().refreshIfDayChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // The bar floats over the content and blurs what is behind it, so there
      // has to be something behind it. Screens that scroll reserve
      // BulkrNavBar.contentInset at the bottom of their list.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<UserScrollNotification>(
          onNotification: _onUserScroll,
          child: IndexedStack(
            index: _currentIndex,
            children: const [
              DashboardScreen(),
              MealsScreen(),
              FeedScreen(),
              TrackerScreen(),
              ProfileScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BulkrNavBar(
        destinations: MainScreen.destinations,
        currentIndex: _currentIndex,
        onSelected: _select,
        compact: _navCompact,
      ),
    );
  }
}
