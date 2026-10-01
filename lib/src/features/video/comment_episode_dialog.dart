import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../domain/models/video.dart';
import '../../core/app_dialog.dart';

Future<VideoCard?> showCommentEpisodeDialog(
  BuildContext context, {
  required List<VideoCard> episodes,
  required String selectedId,
}) =>
    showAppDialog<VideoCard>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.episodeList),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: episodes.length,
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final selected = episode.id == selectedId;
                return ListTile(
                  selected: selected,
                  leading: Icon(selected ? Symbols.play_arrow_rounded : Symbols.video_library_rounded),
                  title: Text(episode.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, episode),
                );
              },
            ),
          ),
        ),
      ),
    );
