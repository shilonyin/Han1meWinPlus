import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/video.dart';
import '../../../l10n/app_localizations.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import '../shared/video_card.dart';
import 'author_controller.dart';

/// 作者页：顶部是作者资料（头像 / 名字 / 影片数 / 订阅），下面是这位作者的影片。
///
/// 为什么要有这一页：以前点作者名是「拿作者名去搜索」——落在一个带分类、排序、
/// 标签的搜索页上，看不出这是谁的页面，而且模糊匹配会混进别人的片子。这里换成
/// 作者自己的页面（用户对着 B 站的空间页提出的要求）。
class AuthorPage extends ConsumerStatefulWidget {
  const AuthorPage({super.key, required this.artist});

  final String artist;

  @override
  ConsumerState<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends ConsumerState<AuthorPage> {
  /// 订阅状态的本地乐观值：点下去立刻变，请求失败再翻回来。
  bool? _override;

  bool _persisted() {
    final account = ref.watch(accountProvider).valueOrNull;
    final remote = account == null
        ? null
        : ref.watch(remoteLibraryProvider).valueOrNull;
    final library = ref.watch(libraryProvider).value ?? const LibraryState();
    final expected = widget.artist.trim().toLowerCase();
    return (remote?.subscriptionArtists ?? library.artists).any(
      (item) => item.name.trim().toLowerCase() == expected,
    );
  }

  /// 已登录时要有 artistId / token / userId 才能调站点的订阅接口；缺一个就只能
  /// 禁用按钮 —— 点了没反应比按钮灰着更让人困惑。
  bool _canSubscribe(VideoDetail profile) {
    final account = ref.read(accountProvider).valueOrNull;
    if (account == null) return true;
    return profile.artistId != null &&
        (profile.csrfToken ?? account.csrfToken) != null &&
        (profile.subscriptionUserId ?? profile.currentUserId ?? account.id) !=
            null;
  }

  Future<void> _toggleSubscription(VideoDetail profile) async {
    final account = ref.read(accountProvider).valueOrNull;
    final enabled = !(_override ?? _persisted());
    setState(() => _override = enabled);
    try {
      if (account == null) {
        // 未登录：只记在本地库里，和详情页作者卡一致。
        await ref
            .read(libraryProvider.notifier)
            .setSubscription(profile, enabled);
        return;
      }
      final settings = await ref.read(settingsProvider.future);
      await ref
          .read(han1meRepositoryProvider)
          .setSubscription(
            settings.resolvedBaseUrl,
            profile.csrfToken ?? account.csrfToken!,
            profile.subscriptionUserId ?? profile.currentUserId ?? account.id!,
            profile.artistId!,
            enabled,
          );
      ref.invalidate(remoteLibraryProvider);
    } catch (_) {
      if (mounted) setState(() => _override = !enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final async = ref.watch(authorVideosProvider(widget.artist));
    final data = async.valueOrNull;
    final firstId = (data != null && data.items.isNotEmpty)
        ? data.items.first.id
        : '';
    final profile = ref.watch(authorProfileProvider(firstId)).valueOrNull;
    final subscribed = _override ?? _persisted();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.author)),
      body: Column(
        children: [
          _header(theme, l10n, data, profile, subscribed),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.loadFailed('$error'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    PressScale(
                      child: FilledButton.tonal(
                        onPressed: () => ref.invalidate(
                          authorVideosProvider(widget.artist),
                        ),
                        child: Text(l10n.retry),
                      ),
                    ),
                  ],
                ),
              ),
              data: (value) => value.items.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noSearchResults,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : VideoCardGrid(
                      videos: value.items,
                      horizontal: true,
                      bottomPadding: 16,
                    ),
            ),
          ),
          if (data != null && data.hasMore) _moreBar(l10n, data),
        ],
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    AppLocalizations l10n,
    AuthorVideos? data,
    VideoDetail? profile,
    bool subscribed,
  ) {
    final avatar = profile?.artistAvatarUrl;
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: hasAvatar ? appNetworkImage(avatar) : null,
            child: hasAvatar
                ? null
                : Text(
                    widget.artist.isEmpty
                        ? '?'
                        : widget.artist.characters.first,
                    style: theme.textTheme.headlineSmall,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.artist,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 站点只在个人编辑页上给订阅者数，别人的订阅数拿不到，
                // 所以这里只报这次拿到的影片数。
                if (data != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.videoCount(data.items.length),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (profile != null)
            PressScale(
              child: FilledButton.tonal(
                onPressed: _canSubscribe(profile)
                    ? () => _toggleSubscription(profile)
                    : null,
                child: Text(subscribed ? l10n.subscribed : l10n.subscribe),
              ),
            ),
        ],
      ),
    );
  }

  /// 「查看更多」：站点是分页的，网格本身不能滚动到底自动续（见 `VideoCardGrid`），
  /// 所以把入口放在页面底部。
  Widget _moreBar(AppLocalizations l10n, AuthorVideos data) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        child: PressScale(
          child: FilledButton.tonalIcon(
            onPressed: data.loadingMore
                ? null
                : () => ref
                      .read(authorVideosProvider(widget.artist).notifier)
                      .loadMore(),
            icon: data.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.expand_more_rounded),
            label: Text(l10n.more),
          ),
        ),
      ),
    ),
  );
}
