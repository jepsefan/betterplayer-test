import 'dart:convert';
import 'dart:io';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'better_player_subtitle.dart';

class BetterPlayerSubtitlesFactory {
  static Future<List<BetterPlayerSubtitle>> parseSubtitles(
      BetterPlayerSubtitlesSource source) async {
    switch (source.type) {
      case BetterPlayerSubtitlesSourceType.file:
        return _parseSubtitlesFromFile(source);
      case BetterPlayerSubtitlesSourceType.network:
        return _parseSubtitlesFromNetwork(source);
      case BetterPlayerSubtitlesSourceType.memory:
        return _parseSubtitlesFromMemory(source);
      default:
        return [];
    }
  }

  static Future<List<BetterPlayerSubtitle>> _parseSubtitlesFromFile(
      BetterPlayerSubtitlesSource source) async {
    try {
      final List<BetterPlayerSubtitle> subtitles = [];
      for (final String? url in source.urls!) {
        final file = File(url!);
        if (file.existsSync()) {
          final String fileContent = await file.readAsString();
          final subtitlesCache = _parseString(fileContent);
          subtitles.addAll(subtitlesCache);
        } else {
          BetterPlayerUtils.log("$url doesn't exist!");
        }
      }
      return subtitles;
    } catch (exception) {
      BetterPlayerUtils.log("Failed to read subtitles from file: $exception");
    }
    return [];
  }

  static Future<List<BetterPlayerSubtitle>> _parseSubtitlesFromNetwork(
      BetterPlayerSubtitlesSource source) async {
    try {
      final client = HttpClient();
      final List<BetterPlayerSubtitle> subtitles = [];
      for (final String? url in source.urls!) {
        final request = await client.getUrl(Uri.parse(url!));
        source.headers?.keys.forEach((key) {
          final value = source.headers![key];
          if (value != null) {
            request.headers.add(key, value);
          }
        });
        final response = await request.close();
        final data = await response.transform(const Utf8Decoder()).join();
        final cacheList = _parseString(data);
        subtitles.addAll(cacheList);
      }
      client.close();

      BetterPlayerUtils.log("Parsed total subtitles: ${subtitles.length}");
      return subtitles;
    } catch (exception) {
      BetterPlayerUtils.log(
          "Failed to read subtitles from network: $exception");
    }
    return [];
  }

  static List<BetterPlayerSubtitle> _parseSubtitlesFromMemory(
      BetterPlayerSubtitlesSource source) {
    try {
      return _parseString(source.content!);
    } catch (exception) {
      BetterPlayerUtils.log("Failed to read subtitles from memory: $exception");
    }
    return [];
  }

  static List<BetterPlayerSubtitle> _parseString(String value) {
    final normalized = value.replaceAll('\r\n', '\n');
    final bool isWebVTT = normalized.trimLeft().startsWith("WEBVTT");

    final List<String> components =
        isWebVTT ? _parseWebVttComponents(normalized) : normalized.split('\n\n');

    // Skip parsing files with no cues
    if (components.isEmpty) {
      return [];
    }

    final List<BetterPlayerSubtitle> subtitlesObj = [];

    for (final component in components) {
      if (component.trim().isEmpty || component.trim() == "WEBVTT") {
        continue;
      }
      final subtitle = BetterPlayerSubtitle(component, isWebVTT);
      if (subtitle.start != null &&
          subtitle.end != null &&
          subtitle.texts != null) {
        subtitlesObj.add(subtitle);
      }
    }

    return subtitlesObj;
  }

  ///Build WebVTT cue components line-by-line instead of treating every blank
  ///line as an unconditional cue boundary.
  ///
  ///Some subtitle providers emit visual status text as multiple blank-line
  ///separated blocks under one timestamp. Those continuation blocks have no
  ///timestamp of their own and should remain part of the preceding cue until
  ///the next timestamp is encountered.
  static List<String> _parseWebVttComponents(String value) {
    final lines = value.split('\n');
    final components = <String>[];
    final current = <String>[];

    bool hasTimestamp = false;

    void flush() {
      if (hasTimestamp && current.isNotEmpty) {
        while (current.isNotEmpty && current.last.isEmpty) {
          current.removeLast();
        }
        if (current.isNotEmpty) {
          components.add(current.join('\n'));
        }
      }
      current.clear();
      hasTimestamp = false;
    }

    for (final rawLine in lines) {
      final line = rawLine;
      final trimmed = line.trim();

      if (trimmed == "WEBVTT") {
        continue;
      }

      // Ignore WebVTT metadata blocks rather than appending them as dialogue.
      if (trimmed.startsWith("NOTE") ||
          trimmed == "STYLE" ||
          trimmed == "REGION") {
        continue;
      }

      if (line.contains(BetterPlayerSubtitle.timerSeparator)) {
        flush();
        current.add(line);
        hasTimestamp = true;
        continue;
      }

      if (hasTimestamp) {
        // Preserve internal blank lines. HtmlWidget/layout can then retain the
        // intended separation between status fields such as Attack/Defense.
        current.add(line);
      }
    }

    flush();
    return components;
  }
