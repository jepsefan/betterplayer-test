import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/subtitles/better_player_subtitle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class BetterPlayerSubtitlesDrawer extends StatefulWidget {
  final List<BetterPlayerSubtitle> subtitles;
  final BetterPlayerController betterPlayerController;
  final BetterPlayerSubtitlesConfiguration? betterPlayerSubtitlesConfiguration;
  final Stream<bool> playerVisibilityStream;

  const BetterPlayerSubtitlesDrawer({
    Key? key,
    required this.subtitles,
    required this.betterPlayerController,
    this.betterPlayerSubtitlesConfiguration,
    required this.playerVisibilityStream,
  }) : super(key: key);

  @override
  _BetterPlayerSubtitlesDrawerState createState() =>
      _BetterPlayerSubtitlesDrawerState();
}

class _BetterPlayerSubtitlesDrawerState
    extends State<BetterPlayerSubtitlesDrawer> {
  late TextStyle _innerTextStyle;
  late TextStyle _outerTextStyle;

  VideoPlayerValue? _latestValue;
  BetterPlayerSubtitlesConfiguration? _configuration;
  bool _playerVisible = false;
  late StreamSubscription _visibilityStreamSubscription;

  @override
  void initState() {
    _visibilityStreamSubscription =
        widget.playerVisibilityStream.listen((state) {
      if (mounted) {
        setState(() {
          _playerVisible = state;
        });
      }
    });

    _configuration = widget.betterPlayerSubtitlesConfiguration ??
        setupDefaultConfiguration();

    widget.betterPlayerController.videoPlayerController!
        .addListener(_updateState);

    _outerTextStyle = TextStyle(
        fontSize: _configuration!.fontSize,
        fontFamily: _configuration!.fontFamily,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _configuration!.outlineSize
          ..color = _configuration!.outlineColor);

    _innerTextStyle = TextStyle(
        fontFamily: _configuration!.fontFamily,
        color: _configuration!.fontColor,
        fontSize: _configuration!.fontSize);

    super.initState();
  }

  @override
  void dispose() {
    widget.betterPlayerController.videoPlayerController!
        .removeListener(_updateState);
    _visibilityStreamSubscription.cancel();
    super.dispose();
  }

  void _updateState() {
    if (mounted) {
      setState(() {
        _latestValue =
            widget.betterPlayerController.videoPlayerController!.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BetterPlayerSubtitleRenderer>(
      valueListenable: widget.betterPlayerController.subtitleRenderer,
      builder: (context, renderer, child) {
        if (renderer == BetterPlayerSubtitleRenderer.stableOverlap) {
          return _buildStableOverlap();
        }
        return _buildDefault();
      },
    );
  }

  Widget _buildDefault() {
    final BetterPlayerSubtitle? subtitle = _getSubtitleAtCurrentPosition();
    widget.betterPlayerController.renderedSubtitle = subtitle;
    final List<String> subtitles = subtitle?.texts ?? [];
    final List<Widget> textWidgets =
        subtitles.map((text) => _buildSubtitleTextWidget(text)).toList();

    return Container(
      height: double.infinity,
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: _effectiveBottomPadding,
            left: _configuration!.leftPadding,
            right: _configuration!.rightPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: textWidgets,
        ),
      ),
    );
  }

  Widget _buildStableOverlap() {
    if (_latestValue == null) {
      widget.betterPlayerController.renderedSubtitle = null;
      return const SizedBox.expand();
    }

    final position = _latestValue!.position;
    final group = _overlapGroupAt(position);
    if (group.isEmpty) {
      widget.betterPlayerController.renderedSubtitle = null;
      return const SizedBox.expand();
    }

    final active = group
        .where((entry) => _isActive(entry.subtitle, position))
        .toList();
    widget.betterPlayerController.renderedSubtitle =
        active.isEmpty ? null : active.last.subtitle;

    final startCounts = <Duration, int>{};
    for (final entry in group) {
      final start = entry.subtitle.start;
      if (start != null) {
        startCounts[start] = (startCounts[start] ?? 0) + 1;
      }
    }

    final statusStarts = startCounts.entries
        .where((entry) => entry.value >= 5)
        .map((entry) => entry.key)
        .toSet();

    final statusEntries = group
        .where((entry) => statusStarts.contains(entry.subtitle.start))
        .toList();
    final normalEntries = group
        .where((entry) => !statusStarts.contains(entry.subtitle.start))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: _effectiveBottomPadding,
        left: _configuration!.leftPadding,
        right: _configuration!.rightPadding,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (normalEntries.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: normalEntries
                    .map((entry) => _buildReservedCue(entry, position,
                        alignment: _configuration!.alignment))
                    .toList(),
              ),
            ),
          if (statusEntries.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: statusEntries
                    .map((entry) => _buildReservedCue(entry, position,
                        alignment: Alignment.centerLeft))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  double get _effectiveBottomPadding => _playerVisible
      ? _configuration!.bottomPadding + 30
      : _configuration!.bottomPadding;

  Widget _buildReservedCue(
    _IndexedSubtitle entry,
    Duration position, {
    required Alignment alignment,
  }) {
    final visible = _isActive(entry.subtitle, position);
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: entry.subtitle.texts
            .map((text) =>
                _buildSubtitleTextWidget(text, alignment: alignment))
            .toList(),
      ),
    );
  }

  List<_IndexedSubtitle> _overlapGroupAt(Duration position) {
    final lines = widget.betterPlayerController.subtitlesLines;
    final indexed = <_IndexedSubtitle>[];

    for (var i = 0; i < lines.length; i++) {
      if (lines[i].start != null && lines[i].end != null) {
        indexed.add(_IndexedSubtitle(i, lines[i]));
      }
    }

    indexed.sort((a, b) {
      final byStart = a.subtitle.start!.compareTo(b.subtitle.start!);
      return byStart != 0 ? byStart : a.index.compareTo(b.index);
    });

    final groups = <List<_IndexedSubtitle>>[];
    var current = <_IndexedSubtitle>[];
    Duration? groupEnd;

    for (final entry in indexed) {
      if (current.isEmpty) {
        current = [entry];
        groupEnd = entry.subtitle.end;
        continue;
      }

      if (entry.subtitle.start! <= groupEnd!) {
        current.add(entry);
        if (entry.subtitle.end! > groupEnd) {
          groupEnd = entry.subtitle.end;
        }
      } else {
        groups.add(current);
        current = [entry];
        groupEnd = entry.subtitle.end;
      }
    }
    if (current.isNotEmpty) groups.add(current);

    for (final group in groups) {
      final start = group.first.subtitle.start!;
      var end = group.first.subtitle.end!;
      for (final entry in group.skip(1)) {
        if (entry.subtitle.end! > end) end = entry.subtitle.end!;
      }
      if (position >= start && position <= end) {
        return group;
      }
    }
    return const [];
  }

  bool _isActive(BetterPlayerSubtitle subtitle, Duration position) {
    return subtitle.start! <= position && subtitle.end! >= position;
  }

  BetterPlayerSubtitle? _getSubtitleAtCurrentPosition() {
    if (_latestValue == null) {
      return null;
    }

    final Duration position = _latestValue!.position;
    for (final BetterPlayerSubtitle subtitle
        in widget.betterPlayerController.subtitlesLines) {
      if (subtitle.start! <= position && subtitle.end! >= position) {
        return subtitle;
      }
    }
    return null;
  }

  Widget _buildSubtitleTextWidget(String subtitleText,
      {Alignment? alignment}) {
    return Row(children: [
      Expanded(
        child: Align(
          alignment: alignment ?? _configuration!.alignment,
          child: _getTextWithStroke(subtitleText),
        ),
      ),
    ]);
  }

  Widget _getTextWithStroke(String subtitleText) {
    return Container(
      color: _configuration!.backgroundColor,
      child: Stack(
        children: [
          if (_configuration!.outlineEnabled)
            _buildHtmlWidget(subtitleText, _outerTextStyle)
          else
            const SizedBox(),
          _buildHtmlWidget(subtitleText, _innerTextStyle)
        ],
      ),
    );
  }

  Widget _buildHtmlWidget(String text, TextStyle textStyle) {
    return HtmlWidget(
      text,
      textStyle: textStyle,
    );
  }

  BetterPlayerSubtitlesConfiguration setupDefaultConfiguration() {
    return const BetterPlayerSubtitlesConfiguration();
  }
}

class _IndexedSubtitle {
  final int index;
  final BetterPlayerSubtitle subtitle;

  const _IndexedSubtitle(this.index, this.subtitle);
}
