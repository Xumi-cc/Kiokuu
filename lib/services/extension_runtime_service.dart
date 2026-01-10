import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/extension_model.dart';

/// Service that manages and executes user-imported extensions
///
/// Extensions are JSON-based configuration files that define:
/// - How to scrape track metadata from URLs
/// - How to search for tracks
/// - How to get download/stream URLs
///
/// This approach is simpler, safer, and doesn't require a scripting runtime
class ExtensionRuntimeService {
  static final ExtensionRuntimeService instance = ExtensionRuntimeService._();
  ExtensionRuntimeService._();

  String? _extensionsPath;
  final Map<String, ExtensionMetadata> _extensions = {};
  final Map<String, ExtensionConfig> _extensionConfigs = {};
  final http.Client _httpClient = http.Client();

  static const String _metadataKey = 'installed_extensions_v2';

  /// Initialize the extension runtime
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('⚠️ Extensions not supported on web');
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      _extensionsPath = '${appDir.path}/user_extensions';

      final extDir = Directory(_extensionsPath!);
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      await _loadInstalledExtensions();
      debugPrint(
        '🔌 ExtensionRuntime initialized with ${_extensions.length} extensions',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to initialize ExtensionRuntime: $e');
    }
  }

  /// Load all installed extensions from disk
  Future<void> _loadInstalledExtensions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = prefs.getString(_metadataKey);

      if (metadataJson != null) {
        final List<dynamic> metadataList = jsonDecode(metadataJson);
        for (final meta in metadataList) {
          final metadata = ExtensionMetadata.fromJson(
            meta as Map<String, dynamic>,
          );
          _extensions[metadata.id] = metadata;

          // Load the config file
          final configFile = File(
            '$_extensionsPath/${metadata.id}/config.json',
          );
          if (await configFile.exists()) {
            final configJson = jsonDecode(await configFile.readAsString());
            _extensionConfigs[metadata.id] = ExtensionConfig.fromJson(
              configJson,
            );
            debugPrint('✅ Loaded extension: ${metadata.name}');
          } else {
            debugPrint('⚠️ Config not found for: ${metadata.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load extensions: $e');
    }
  }

  /// Save extension metadata to preferences
  Future<void> _saveMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataList = _extensions.values.map((e) => e.toJson()).toList();
      await prefs.setString(_metadataKey, jsonEncode(metadataList));
    } catch (e) {
      debugPrint('⚠️ Failed to save extension metadata: $e');
    }
  }

  /// Import an extension from a file path
  /// Expects a .json config file
  Future<ExtensionResult<ExtensionMetadata>> importExtension(
    String filePath,
  ) async {
    if (_extensionsPath == null) {
      return ExtensionResult.failure('Extension system not initialized');
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ExtensionResult.failure('File not found: $filePath');
      }

      final fileName = file.path.split('/').last;

      if (!fileName.endsWith('.json')) {
        return ExtensionResult.failure(
          'Unsupported file type. Use .json extension config files.',
        );
      }

      final content = await file.readAsString();
      return await _processExtensionJson(content);
    } catch (e) {
      debugPrint('⚠️ Failed to import extension: $e');
      return ExtensionResult.failure('Import failed: $e');
    }
  }

  /// Internal: Process extension JSON content (shared by import and update)
  Future<ExtensionResult<ExtensionMetadata>> _processExtensionJson(
    String content,
  ) async {
    try {
      final Map<String, dynamic> configJson = jsonDecode(content);

      // Parse and validate config
      final config = ExtensionConfig.fromJson(configJson);
      final metadata = ExtensionMetadata(
        id: config.id,
        name: config.name,
        description: config.description,
        version: config.version,
        author: config.author,
        homepage: config.homepage,
        iconUrl: config.iconUrl,
        type: config.type,
        capabilities: [
          ExtensionCapability.http,
          ExtensionCapability.htmlParsing,
        ],
        supportedDomains: config.supportedDomains,
        installedAt: DateTime.now(),
        updateUrl: config.updateUrl,
      );

      final extDir = Directory('$_extensionsPath/${metadata.id}');
      if (await extDir.exists()) {
        // Update existing extension
        await extDir.delete(recursive: true);
      }
      await extDir.create(recursive: true);

      // Save config
      final configFile = File('${extDir.path}/config.json');
      await configFile.writeAsString(content);

      // Register extension
      _extensions[metadata.id] = metadata;
      _extensionConfigs[metadata.id] = config;
      await _saveMetadata();

      debugPrint('✅ Processed extension: ${metadata.name}');
      return ExtensionResult.success(metadata);
    } catch (e) {
      debugPrint('⚠️ Failed to process extension JSON: $e');
      return ExtensionResult.failure('Processing failed: $e');
    }
  }

  /// Import an extension from raw JSON string (for bundled assets)
  Future<ExtensionResult<ExtensionMetadata>> importExtensionFromJson(
    String jsonContent,
  ) async {
    return _processExtensionJson(jsonContent);
  }

  /// Check for updates for all extensions that have a remote update URL
  Future<Map<String, String>> checkForUpdates() async {
    final Map<String, String> updates = {};
    for (final ext in _extensions.values) {
      if (ext.updateUrl != null) {
        try {
          final response = await _httpClient
              .get(Uri.parse(ext.updateUrl!))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final remoteJson = jsonDecode(response.body);
            final remoteVersion = remoteJson['version'] as String?;
            if (remoteVersion != null &&
                _isNewerVersion(ext.version, remoteVersion)) {
              updates[ext.id] = remoteVersion;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Update check failed for ${ext.name}: $e');
        }
      }
    }
    return updates;
  }

  /// Check for update for a single extension by ID
  Future<String?> checkForUpdateSingle(String id) async {
    final ext = _extensions[id];
    if (ext == null || ext.updateUrl == null) {
      return null;
    }

    try {
      final response = await _httpClient
          .get(Uri.parse(ext.updateUrl!))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final remoteJson = jsonDecode(response.body);
        final remoteVersion = remoteJson['version'] as String?;
        if (remoteVersion != null &&
            _isNewerVersion(ext.version, remoteVersion)) {
          return remoteVersion;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Update check failed for ${ext.name}: $e');
    }
    return null;
  }

  /// Update an extension from its remote URL
  Future<ExtensionResult<ExtensionMetadata>> updateExtension(String id) async {
    final ext = _extensions[id];
    if (ext == null || ext.updateUrl == null) {
      return ExtensionResult.failure('Extension has no update URL');
    }

    try {
      final response = await _httpClient
          .get(Uri.parse(ext.updateUrl!))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ExtensionResult.failure(
          'Failed to fetch update: ${response.statusCode}',
        );
      }

      final content = response.body;
      return await _processExtensionJson(content);
    } catch (e) {
      return ExtensionResult.failure('Update failed: $e');
    }
  }

  bool _isNewerVersion(String current, String remote) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final remoteParts = remote.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        if (r > c) return true;
        if (c > r) return false;
      }
      return false;
    } catch (e) {
      return remote != current;
    }
  }

  /// Remove an installed extension
  Future<bool> removeExtension(String extensionId) async {
    if (_extensionsPath == null) return false;

    try {
      final extDir = Directory('$_extensionsPath/$extensionId');
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }

      _extensions.remove(extensionId);
      _extensionConfigs.remove(extensionId);
      await _saveMetadata();

      debugPrint('🗑️ Removed extension: $extensionId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to remove extension: $e');
      return false;
    }
  }

  /// Enable or disable an extension
  Future<void> setExtensionEnabled(String extensionId, bool enabled) async {
    final ext = _extensions[extensionId];
    if (ext != null) {
      _extensions[extensionId] = ext.copyWith(isEnabled: enabled);
      await _saveMetadata();
    }
  }

  /// Get all installed extensions
  List<ExtensionMetadata> get installedExtensions =>
      _extensions.values.toList();

  /// Get enabled extensions
  List<ExtensionMetadata> get enabledExtensions =>
      _extensions.values.where((e) => e.isEnabled).toList();

  /// Get extension by ID
  ExtensionMetadata? getExtension(String id) => _extensions[id];

  /// Get extension config by ID
  ExtensionConfig? getExtensionConfig(String id) => _extensionConfigs[id];

  /// Find extension that supports a given URL
  ExtensionMetadata? findExtensionForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final domain = uri.host;
    for (final ext in enabledExtensions) {
      for (final supported in ext.supportedDomains) {
        if (domain.contains(supported) || supported.contains(domain)) {
          return ext;
        }
      }
    }
    return null;
  }

  /// Execute extension's scrape function for a URL
  Future<ExtensionResult<ScrapedTrack>> scrapeUrl(
    String extensionId,
    String url,
  ) async {
    final config = _extensionConfigs[extensionId];
    if (config == null) {
      return ExtensionResult.failure('Extension not found: $extensionId');
    }

    if (config.scrapeConfig == null) {
      return ExtensionResult.failure('Extension does not support scraping');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Fetch the page
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: config.defaultHeaders,
      );

      if (response.statusCode != 200) {
        return ExtensionResult.failure('HTTP ${response.statusCode}');
      }

      final html = response.body;
      final track = _extractTrackFromHtml(html, url, config.scrapeConfig!);

      stopwatch.stop();

      if (track != null) {
        return ExtensionResult.success(track, executionTime: stopwatch.elapsed);
      }

      return ExtensionResult.failure('Failed to extract track info');
    } catch (e) {
      return ExtensionResult.failure('Scrape failed: $e');
    }
  }

  /// Extract track info from HTML using scrape config
  ScrapedTrack? _extractTrackFromHtml(
    String html,
    String url,
    ScrapeConfig config,
  ) {
    final document = html_parser.parse(html);

    String? extract(SelectorConfig? selector) {
      if (selector == null) return null;

      final element = document.querySelector(selector.selector);
      if (element == null) return null;

      String? value;
      if (selector.attribute != null) {
        value = element.attributes[selector.attribute];
      } else {
        value = element.text.trim();
      }

      // Apply regex if specified
      if (value != null && selector.regex != null) {
        final match = RegExp(selector.regex!).firstMatch(value);
        if (match != null) {
          value = match.group(selector.regexGroup ?? 0);
        }
      }

      return value;
    }

    final id = extract(config.id) ?? _generateIdFromUrl(url);
    final title = extract(config.title);
    final artist = extract(config.artist);

    if (title == null || artist == null) {
      return null;
    }

    return ScrapedTrack(
      id: id,
      title: title,
      artist: artist,
      album: extract(config.album),
      coverUrl: extract(config.coverUrl),
      durationMs: int.tryParse(extract(config.duration) ?? ''),
      streamUrl: extract(config.streamUrl),
      downloadUrl: extract(config.downloadUrl),
    );
  }

  String _generateIdFromUrl(String url) {
    return url.hashCode.abs().toString();
  }

  /// Execute extension's search function
  Future<ExtensionResult<ExtensionSearchResult>> search(
    String extensionId,
    String query, {
    int page = 1,
  }) async {
    final config = _extensionConfigs[extensionId];
    if (config == null) {
      return ExtensionResult.failure('Extension not found: $extensionId');
    }

    if (config.searchConfig == null) {
      return ExtensionResult.failure('Extension does not support search');
    }

    final stopwatch = Stopwatch()..start();

    try {
      final searchConfig = config.searchConfig!;

      // Build search URL
      var searchUrl = searchConfig.urlTemplate
          .replaceAll('{query}', Uri.encodeComponent(query))
          .replaceAll('{page}', page.toString());

      final response = await _httpClient.get(
        Uri.parse(searchUrl),
        headers: config.defaultHeaders,
      );

      if (response.statusCode != 200) {
        return ExtensionResult.failure('HTTP ${response.statusCode}');
      }

      List<ScrapedTrack> tracks;

      if (searchConfig.responseType == 'json') {
        tracks = _extractTracksFromJson(response.body, searchConfig);
      } else {
        tracks = _extractTracksFromHtml(response.body, searchConfig);
      }

      stopwatch.stop();

      return ExtensionResult.success(
        ExtensionSearchResult(
          tracks: tracks,
          page: page,
          hasMore: tracks.isNotEmpty,
        ),
        executionTime: stopwatch.elapsed,
      );
    } catch (e) {
      return ExtensionResult.failure('Search failed: $e');
    }
  }

  /// Extract tracks from JSON response
  List<ScrapedTrack> _extractTracksFromJson(String json, SearchConfig config) {
    try {
      final data = jsonDecode(json);

      // Navigate to the tracks array using the path
      dynamic tracksData = data;
      if (config.resultsPath != null) {
        for (final key in config.resultsPath!.split('.')) {
          if (tracksData is Map) {
            tracksData = tracksData[key];
          } else if (tracksData is List && int.tryParse(key) != null) {
            tracksData = tracksData[int.parse(key)];
          }
        }
      }

      if (tracksData is! List) return [];

      return tracksData
          .map<ScrapedTrack?>((item) {
            if (item is! Map<String, dynamic>) return null;

            String? getValue(String? path) {
              if (path == null) return null;
              dynamic value = item;
              for (final key in path.split('.')) {
                if (value is Map) {
                  value = value[key];
                } else {
                  return null;
                }
              }
              return value?.toString();
            }

            final id = getValue(config.trackMapping?['id']);
            final title = getValue(config.trackMapping?['title']);
            final artist = getValue(config.trackMapping?['artist']);

            if (id == null || title == null || artist == null) return null;

            return ScrapedTrack(
              id: id,
              title: title,
              artist: artist,
              album: getValue(config.trackMapping?['album']),
              coverUrl: getValue(config.trackMapping?['cover']),
              durationMs: int.tryParse(
                getValue(config.trackMapping?['duration']) ?? '',
              ),
              streamUrl: getValue(config.trackMapping?['streamUrl']),
              downloadUrl: getValue(config.trackMapping?['downloadUrl']),
            );
          })
          .whereType<ScrapedTrack>()
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to parse JSON: $e');
      return [];
    }
  }

  /// Extract tracks from HTML response
  List<ScrapedTrack> _extractTracksFromHtml(String html, SearchConfig config) {
    try {
      final document = html_parser.parse(html);
      final trackElements = document.querySelectorAll(
        config.trackSelector ?? '.track',
      );

      return trackElements
          .map<ScrapedTrack?>((element) {
            String? extract(String? selector, String? attribute) {
              if (selector == null) return null;
              final el = element.querySelector(selector);
              if (el == null) return null;
              return attribute != null
                  ? el.attributes[attribute]
                  : el.text.trim();
            }

            final mapping = config.trackMapping ?? {};
            final id = extract(mapping['id'], mapping['idAttr']);
            final title = extract(mapping['title'], mapping['titleAttr']);
            final artist = extract(mapping['artist'], mapping['artistAttr']);

            if (title == null || artist == null) return null;

            return ScrapedTrack(
              id: id ?? element.hashCode.abs().toString(),
              title: title,
              artist: artist,
              album: extract(mapping['album'], mapping['albumAttr']),
              coverUrl: extract(mapping['cover'], mapping['coverAttr']),
              durationMs: int.tryParse(
                extract(mapping['duration'], null) ?? '',
              ),
            );
          })
          .whereType<ScrapedTrack>()
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to parse HTML: $e');
      return [];
    }
  }

  /// Execute extension's getDownloadUrl function
  /// Returns DownloadInfo with URL and audio metadata
  Future<ExtensionResult<DownloadInfo>> getDownloadUrl(
    String extensionId,
    String trackId, {
    Map<String, dynamic>? extra,
  }) async {
    final config = _extensionConfigs[extensionId];
    if (config == null) {
      return ExtensionResult.failure('Extension not found: $extensionId');
    }

    if (config.downloadConfig == null) {
      return ExtensionResult.failure('Extension does not support downloads');
    }

    try {
      final downloadConfig = config.downloadConfig!;
      var idToUse = trackId;

      // 1. Resolution Step (e.g. Spotify -> Tidal ID)
      if (downloadConfig.resolver != null) {
        final resolver = downloadConfig.resolver!;
        final resolverUrl = resolver.urlTemplate.replaceAll('{id}', trackId);

        final resolverResp = await _httpClient.get(
          Uri.parse(resolverUrl),
          headers: config.defaultHeaders,
        );

        if (resolverResp.statusCode == 200) {
          String? resolvedValue;
          if (resolver.responseType == 'json') {
            final data = jsonDecode(resolverResp.body);
            resolvedValue = _getNestedValue(data, resolver.resultPath ?? 'id');
          } else {
            resolvedValue = resolverResp.body;
          }

          if (resolvedValue != null) {
            // Apply regex if provided
            if (resolver.resultRegex != null) {
              final reg = RegExp(resolver.resultRegex!);
              final match = reg.firstMatch(resolvedValue);
              if (match != null) {
                resolvedValue = match.group(resolver.regexGroup ?? 1);
              }
            }

            if (resolvedValue != null) {
              idToUse = resolvedValue;
              debugPrint('✅ Resolved ID $trackId -> $idToUse');
            }
          }
        }
      }

      // 2. Build list of URLs to try (Template + Mirrors)
      List<String> urlsToTry = [];

      // Add primary template if available
      if (downloadConfig.urlTemplate != null) {
        var primaryUrl = downloadConfig.urlTemplate!.replaceAll(
          '{id}',
          Uri.encodeComponent(idToUse),
        );
        // Add any extra params
        if (extra != null) {
          extra.forEach((key, value) {
            primaryUrl = primaryUrl.replaceAll('{$key}', value.toString());
          });
        }
        urlsToTry.add(primaryUrl);
      }

      // 3. Add mirrors if configured (matches backend reliability strategy)
      if (downloadConfig.mirrorListUrl != null) {
        debugPrint('🔍 Fetching mirrors from: ${downloadConfig.mirrorListUrl}');
        try {
          final mirrorResp = await _httpClient.get(
            Uri.parse(downloadConfig.mirrorListUrl!),
          );
          debugPrint('📡 Mirror list response: ${mirrorResp.statusCode}');
          if (mirrorResp.statusCode == 200) {
            final data = jsonDecode(mirrorResp.body);
            debugPrint('📋 Mirror path: ${downloadConfig.mirrorPath}');
            final mirrorsData = _getNestedValue(
              data,
              downloadConfig.mirrorPath ?? '',
            );
            debugPrint('📋 Mirrors data type: ${mirrorsData.runtimeType}');
            debugPrint('📋 Mirrors data: $mirrorsData');

            if (mirrorsData is List) {
              debugPrint('✅ Found ${mirrorsData.length} mirrors');
              for (final mirror in mirrorsData.take(5)) {
                final domain = mirror.toString();
                String mirrorUrl;
                if (downloadConfig.mirrorUrlTemplate != null) {
                  mirrorUrl = downloadConfig.mirrorUrlTemplate!
                      .replaceAll('{domain}', domain)
                      .replaceAll('{id}', idToUse);
                } else {
                  // Fallback to simple domain + ID if no template
                  mirrorUrl = domain.startsWith('http')
                      ? '$domain/track/?id=$idToUse'
                      : 'https://$domain/track/?id=$idToUse';
                }
                debugPrint('➕ Adding mirror URL: $mirrorUrl');
                urlsToTry.add(mirrorUrl);
              }
            } else {
              debugPrint(
                '⚠️ Mirrors data is not a List: ${mirrorsData.runtimeType}',
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to fetch mirrors: $e');
        }
      }

      if (urlsToTry.isEmpty) {
        return ExtensionResult.failure('No download URLs or mirrors available');
      }

      // 4. Try URLs one by one until one works
      String? lastError;
      String? extractedFormat;
      String? extractedCodec;
      int? extractedBitDepth;
      int? extractedSampleRate;
      String? extractedQuality;
      // Track metadata from source
      String? sourceTitle;
      String? sourceArtist;
      String? sourceAlbum;
      String? sourceCoverUrl;
      String? sourceIsrc;

      for (final infoUrl in urlsToTry) {
        try {
          debugPrint('📡 Trying source: $infoUrl');
          final response = await _httpClient.get(
            Uri.parse(infoUrl),
            headers: config.defaultHeaders,
          );

          if (response.statusCode != 200) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }

          String? downloadUrl;
          if (downloadConfig.responseType == 'json') {
            final data = jsonDecode(response.body);

            // Handle Manifest Decoding (e.g. Base64 JSON manifests)
            if (downloadConfig.manifestPath != null) {
              final manifestBase64 = _getNestedValue(
                data,
                downloadConfig.manifestPath!,
              )?.toString();

              if (manifestBase64 != null) {
                try {
                  final manifestJson = utf8.decode(
                    base64.decode(manifestBase64),
                  );
                  final manifestData = jsonDecode(manifestJson);
                  // Support "urls.0" or any other path inside manifest
                  final urls = _getNestedValue(
                    manifestData,
                    downloadConfig.manifestUrlPath ?? 'urls',
                  );
                  if (urls is List && urls.isNotEmpty) {
                    downloadUrl = urls[0].toString();
                  } else {
                    downloadUrl = urls?.toString();
                  }

                  // Extract audio metadata from manifest
                  extractedFormat = manifestData['mimeType']?.toString();
                  extractedCodec = manifestData['codecs']?.toString();

                  // Extract from parent data object (Tidal style)
                  extractedBitDepth = data['data']?['bitDepth'] as int?;
                  extractedSampleRate = data['data']?['sampleRate'] as int?;
                  extractedQuality = data['data']?['audioQuality']?.toString();

                  debugPrint(
                    '🎵 Audio: $extractedFormat, $extractedCodec, ${extractedBitDepth}bit/${extractedSampleRate}Hz',
                  );
                } catch (e) {
                  debugPrint('⚠️ Failed to decode manifest: $e');
                }
              }
            } else {
              downloadUrl = _getNestedValue(
                data,
                downloadConfig.urlPath ?? 'url',
              )?.toString();

              // Try to extract metadata from standard JSON responses
              extractedFormat =
                  data['format']?.toString() ??
                  data['mimeType']?.toString() ??
                  'audio/flac';
              extractedQuality = data['quality']?.toString();
            }
          } else {
            final document = html_parser.parse(response.body);
            final element = document.querySelector(
              downloadConfig.urlSelector ?? 'a[download]',
            );
            downloadUrl = element?.attributes['href'];
          }

          if (downloadUrl != null) {
            // Handle Polling (Asynchronous background tasks)
            if (downloadConfig.isPolling &&
                downloadConfig.pollUrlTemplate != null) {
              final taskId = downloadUrl; // Initial call returns the task ID
              int attempts = 0;
              final maxAttempts = downloadConfig.maxPollAttempts ?? 30;

              while (attempts < maxAttempts) {
                attempts++;
                debugPrint(
                  '⏳ Polling for download ready (attempt $attempts/$maxAttempts)...',
                );
                await Future.delayed(
                  Duration(milliseconds: downloadConfig.pollIntervalMs),
                );

                final pollUrl = downloadConfig.pollUrlTemplate!.replaceAll(
                  '{id}',
                  taskId,
                );
                final pollResp = await _httpClient.get(
                  Uri.parse(pollUrl),
                  headers: config.defaultHeaders,
                );

                if (pollResp.statusCode == 200) {
                  final pollData = jsonDecode(pollResp.body);
                  final status = _getNestedValue(
                    pollData,
                    downloadConfig.pollStatusPath ?? 'status',
                  )?.toString();

                  if (status == (downloadConfig.pollStatusValue ?? 'done')) {
                    final finalUrl = _getNestedValue(
                      pollData,
                      downloadConfig.pollResultPath ??
                          downloadConfig.urlPath ??
                          'url',
                    )?.toString();
                    if (finalUrl != null) {
                      // Fix relative URLs if needed
                      String url = finalUrl;
                      if (finalUrl.startsWith('./') ||
                          finalUrl.startsWith('/')) {
                        final uri = Uri.parse(pollUrl);
                        final base = '${uri.scheme}://${uri.host}';
                        url = finalUrl.startsWith('./')
                            ? '$base/${finalUrl.substring(2)}'
                            : '$base$finalUrl';
                      }
                      return ExtensionResult.success(
                        DownloadInfo(
                          url: url,
                          format: 'audio/flac',
                          quality: 'Ultra HD',
                        ),
                      );
                    }
                  } else if (status == 'error') {
                    lastError = 'Task reported error status';
                    break;
                  }
                }
              }
              lastError = 'Polling timed out';
              continue;
            }

            // 5. Fetch track metadata if infoUrl is configured
            if (downloadConfig.infoUrlTemplate != null) {
              try {
                // Get mirror domain from current URL
                final currentUri = Uri.parse(infoUrl);
                final domain = '${currentUri.scheme}://${currentUri.host}';

                final infoUrlFinal = downloadConfig.infoUrlTemplate!
                    .replaceAll('{domain}', domain)
                    .replaceAll('{id}', idToUse);

                debugPrint('📋 Fetching track info from: $infoUrlFinal');
                final infoResponse = await _httpClient
                    .get(
                      Uri.parse(infoUrlFinal),
                      headers: config.defaultHeaders,
                    )
                    .timeout(const Duration(seconds: 5));

                if (infoResponse.statusCode == 200) {
                  final infoData = jsonDecode(infoResponse.body);

                  sourceTitle = _getNestedValue(
                    infoData,
                    downloadConfig.infoTitlePath ?? 'data.title',
                  )?.toString();

                  sourceArtist = _getNestedValue(
                    infoData,
                    downloadConfig.infoArtistPath ?? 'data.artist.name',
                  )?.toString();

                  sourceAlbum = _getNestedValue(
                    infoData,
                    downloadConfig.infoAlbumPath ?? 'data.album.title',
                  )?.toString();

                  final coverId = _getNestedValue(
                    infoData,
                    downloadConfig.infoCoverPath ?? 'data.album.cover',
                  )?.toString();

                  if (coverId != null) {
                    final prefix =
                        downloadConfig.infoCoverUrlPrefix ??
                        'https://resources.tidal.com/images/';
                    sourceCoverUrl =
                        '$prefix${coverId.replaceAll('-', '/')}/640x640.jpg';
                  }

                  sourceIsrc = _getNestedValue(
                    infoData,
                    downloadConfig.infoIsrcPath ?? 'data.isrc',
                  )?.toString();

                  debugPrint(
                    '📋 Source track: "$sourceTitle" by $sourceArtist',
                  );
                }
              } catch (e) {
                debugPrint('⚠️ Failed to fetch track info: $e');
                // Don't fail the download, just skip metadata
              }
            }

            return ExtensionResult.success(
              DownloadInfo(
                url: downloadUrl,
                format: extractedFormat,
                codec: extractedCodec,
                bitDepth: extractedBitDepth,
                sampleRate: extractedSampleRate,
                quality: extractedQuality,
                sourceTitle: sourceTitle,
                sourceArtist: sourceArtist,
                sourceAlbum: sourceAlbum,
                sourceCoverUrl: sourceCoverUrl,
                sourceIsrc: sourceIsrc,
              ),
            );
          }
        } catch (e) {
          lastError = e.toString();
          continue;
        }
      }

      return ExtensionResult.failure(lastError ?? 'Download URL not found');
    } catch (e) {
      return ExtensionResult.failure('Get download URL failed: $e');
    }
  }

  /// Get nested value from JSON using dot notation path
  dynamic _getNestedValue(dynamic data, String path) {
    if (path.isEmpty) return data;
    dynamic value = data;
    for (final key in path.split('.')) {
      if (value is Map) {
        value = value[key];
      } else if (value is List && int.tryParse(key) != null) {
        value = value[int.parse(key)];
      } else {
        return null;
      }
    }
    return value;
  }

  /// Test an API call directly (for debugging extensions)
  /// Returns the raw JSON response or error
  Future<ExtensionResult<Map<String, dynamic>>> testApiCall(
    String url, {
    Map<String, String>? headers,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint('🔌 Testing API: $url');

      final response = await _httpClient.get(
        Uri.parse(url),
        headers:
            headers ??
            {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': 'application/json',
            },
      );

      stopwatch.stop();
      debugPrint(
        '🔌 Response: ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)',
      );

      if (response.statusCode != 200) {
        return ExtensionResult.failure(
          'HTTP ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        );
      }

      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ExtensionResult.success(data, executionTime: stopwatch.elapsed);
      } catch (e) {
        // Not JSON - return raw body in a wrapper
        return ExtensionResult.success({
          'raw': response.body,
          'contentType': response.headers['content-type'],
        }, executionTime: stopwatch.elapsed);
      }
    } catch (e) {
      return ExtensionResult.failure('API call failed: $e');
    }
  }

  /// Resolve a Spotify URL to Tidal ID using song.link API
  /// This is a built-in utility for extension developers
  Future<ExtensionResult<Map<String, dynamic>>> resolveSonglinkUrl(
    String spotifyUrl,
  ) async {
    final apiUrl =
        'https://api.song.link/v1-alpha.1/links?url=${Uri.encodeComponent(spotifyUrl)}&songIfSingle=true';
    return testApiCall(apiUrl);
  }

  /// Get extensions directory path
  String? get extensionsPath => _extensionsPath;
}

/// Configuration for an extension
class ExtensionConfig {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String? homepage;
  final String? iconUrl;
  final ExtensionType type;
  final List<String> supportedDomains;
  final Map<String, String>? defaultHeaders;
  final ScrapeConfig? scrapeConfig;
  final SearchConfig? searchConfig;
  final DownloadConfig? downloadConfig;

  const ExtensionConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.homepage,
    this.iconUrl,
    required this.type,
    required this.supportedDomains,
    this.defaultHeaders,
    this.scrapeConfig,
    this.searchConfig,
    this.downloadConfig,
    this.updateUrl,
  });

  final String? updateUrl;

  factory ExtensionConfig.fromJson(Map<String, dynamic> json) {
    return ExtensionConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Unknown',
      homepage: json['homepage'] as String?,
      iconUrl: json['icon'] as String?,
      type: ExtensionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ExtensionType.full,
      ),
      supportedDomains:
          (json['domains'] as List<dynamic>?)?.cast<String>() ?? [],
      defaultHeaders: (json['headers'] as Map<String, dynamic>?)
          ?.cast<String, String>(),
      scrapeConfig: json['scrape'] != null
          ? ScrapeConfig.fromJson(json['scrape'] as Map<String, dynamic>)
          : null,
      searchConfig: json['search'] != null
          ? SearchConfig.fromJson(json['search'] as Map<String, dynamic>)
          : null,
      downloadConfig: json['download'] != null
          ? DownloadConfig.fromJson(json['download'] as Map<String, dynamic>)
          : null,
      updateUrl: json['updateUrl'] as String?,
    );
  }
}

/// Configuration for scraping a single track page
class ScrapeConfig {
  final SelectorConfig? id;
  final SelectorConfig? title;
  final SelectorConfig? artist;
  final SelectorConfig? album;
  final SelectorConfig? coverUrl;
  final SelectorConfig? duration;
  final SelectorConfig? streamUrl;
  final SelectorConfig? downloadUrl;

  const ScrapeConfig({
    this.id,
    this.title,
    this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.streamUrl,
    this.downloadUrl,
  });

  factory ScrapeConfig.fromJson(Map<String, dynamic> json) {
    SelectorConfig? parseSelector(dynamic value) {
      if (value == null) return null;
      if (value is String) return SelectorConfig(selector: value);
      if (value is Map<String, dynamic>) return SelectorConfig.fromJson(value);
      return null;
    }

    return ScrapeConfig(
      id: parseSelector(json['id']),
      title: parseSelector(json['title']),
      artist: parseSelector(json['artist']),
      album: parseSelector(json['album']),
      coverUrl: parseSelector(json['cover']),
      duration: parseSelector(json['duration']),
      streamUrl: parseSelector(json['streamUrl']),
      downloadUrl: parseSelector(json['downloadUrl']),
    );
  }
}

/// CSS selector configuration with optional attribute and regex extraction
class SelectorConfig {
  final String selector;
  final String? attribute;
  final String? regex;
  final int? regexGroup;

  const SelectorConfig({
    required this.selector,
    this.attribute,
    this.regex,
    this.regexGroup,
  });

  factory SelectorConfig.fromJson(Map<String, dynamic> json) {
    return SelectorConfig(
      selector: json['selector'] as String,
      attribute: json['attr'] as String?,
      regex: json['regex'] as String?,
      regexGroup: json['regexGroup'] as int?,
    );
  }
}

/// Configuration for search functionality
class SearchConfig {
  final String urlTemplate;
  final String responseType; // 'json' or 'html'
  final String? resultsPath; // JSON path to results array
  final String? trackSelector; // CSS selector for track elements (HTML)
  final Map<String, String>? trackMapping;

  const SearchConfig({
    required this.urlTemplate,
    required this.responseType,
    this.resultsPath,
    this.trackSelector,
    this.trackMapping,
  });

  factory SearchConfig.fromJson(Map<String, dynamic> json) {
    return SearchConfig(
      urlTemplate: json['url'] as String,
      responseType: json['responseType'] as String? ?? 'html',
      resultsPath: json['resultsPath'] as String?,
      trackSelector: json['trackSelector'] as String?,
      trackMapping: (json['mapping'] as Map<String, dynamic>?)
          ?.cast<String, String>(),
    );
  }
}

class DownloadConfig {
  final String? urlTemplate;
  final String responseType; // 'json' or 'html'
  final String? urlPath; // JSON path to download URL
  final String? urlSelector; // CSS selector for download URL (HTML)
  final ResolverConfig? resolver; // Optional resolution step (e.g. Songlink)
  final String? mirrorListUrl; // Optional URL to a JSON list of mirrors
  final String? mirrorPath; // JSON path to domain list in mirrorListUrl
  final String? mirrorUrlTemplate; // Template for mirror URLs
  final String? manifestPath; // If present, decodes this base64 JSON manifest
  final String?
  manifestUrlPath; // JSON path inside decoded manifest to final URL
  final bool isPolling; // If true, polls for status after initial call
  final String? pollUrlTemplate; // URL template to poll for status
  final String? pollStatusPath; // JSON path to check for status
  final String?
  pollStatusValue; // Status value that indicates completion (e.g. "done")
  final String?
  pollResultPath; // JSON path to extract final URL from poll response
  final int? maxPollAttempts; // Maximum number of times to poll
  final int pollIntervalMs; // Interval between polls in milliseconds
  // Track metadata fetching (optional)
  final String?
  infoUrlTemplate; // URL template to fetch track info (e.g. /info/?id={id})
  final String? infoTitlePath; // JSON path to track title
  final String? infoArtistPath; // JSON path to artist name
  final String? infoAlbumPath; // JSON path to album name
  final String? infoCoverPath; // JSON path to cover art URL/ID
  final String? infoCoverUrlPrefix; // Prefix to add to cover ID to make URL
  final String? infoIsrcPath; // JSON path to ISRC

  const DownloadConfig({
    this.urlTemplate,
    required this.responseType,
    this.urlPath,
    this.urlSelector,
    this.resolver,
    this.mirrorListUrl,
    this.mirrorPath,
    this.mirrorUrlTemplate,
    this.manifestPath,
    this.manifestUrlPath,
    this.isPolling = false,
    this.pollUrlTemplate,
    this.pollStatusPath,
    this.pollStatusValue,
    this.pollResultPath,
    this.maxPollAttempts,
    this.pollIntervalMs = 3000,
    this.infoUrlTemplate,
    this.infoTitlePath,
    this.infoArtistPath,
    this.infoAlbumPath,
    this.infoCoverPath,
    this.infoCoverUrlPrefix,
    this.infoIsrcPath,
  });

  factory DownloadConfig.fromJson(Map<String, dynamic> json) {
    return DownloadConfig(
      urlTemplate: json['url'] as String?,
      responseType: json['responseType'] as String? ?? 'json',
      urlPath: json['urlPath'] as String?,
      urlSelector: json['urlSelector'] as String?,
      resolver: json['resolver'] != null
          ? ResolverConfig.fromJson(json['resolver'] as Map<String, dynamic>)
          : null,
      mirrorListUrl: json['mirrorListUrl'] as String?,
      mirrorPath: json['mirrorPath'] as String?,
      mirrorUrlTemplate: json['mirrorUrlTemplate'] as String?,
      manifestPath: json['manifestPath'] as String?,
      manifestUrlPath: json['manifestUrlPath'] as String?,
      isPolling: json['isPolling'] as bool? ?? false,
      pollUrlTemplate: json['pollUrl'] as String?,
      pollStatusPath: json['pollStatusPath'] as String?,
      pollStatusValue: json['pollStatusValue'] as String?,
      pollResultPath: json['pollResultPath'] as String?,
      maxPollAttempts: json['maxPollAttempts'] as int?,
      pollIntervalMs: json['pollInterval'] as int? ?? 3000,
      infoUrlTemplate: json['infoUrl'] as String?,
      infoTitlePath: json['infoTitlePath'] as String?,
      infoArtistPath: json['infoArtistPath'] as String?,
      infoAlbumPath: json['infoAlbumPath'] as String?,
      infoCoverPath: json['infoCoverPath'] as String?,
      infoCoverUrlPrefix: json['infoCoverUrlPrefix'] as String?,
      infoIsrcPath: json['infoIsrcPath'] as String?,
    );
  }
}

/// Configuration for resolving an ID (e.g. Spotify -> Tidal ID via Songlink)
class ResolverConfig {
  final String urlTemplate;
  final String responseType; // 'json' or 'html'
  final String? resultPath; // JSON path to extract
  final String? resultRegex; // Regex to extract from response
  final int? regexGroup;

  const ResolverConfig({
    required this.urlTemplate,
    required this.responseType,
    this.resultPath,
    this.resultRegex,
    this.regexGroup,
  });

  factory ResolverConfig.fromJson(Map<String, dynamic> json) {
    return ResolverConfig(
      urlTemplate: json['url'] as String,
      responseType: json['responseType'] as String? ?? 'json',
      resultPath: json['resultPath'] as String?,
      resultRegex: json['regex'] as String?,
      regexGroup: json['regexGroup'] as int?,
    );
  }
}

/// Information about a download including URL and audio metadata
class DownloadInfo {
  final String url;
  final String? format;
  final String? codec;
  final int? bitDepth;
  final int? sampleRate;
  final String? quality;
  // Track metadata from source
  final String? sourceTitle;
  final String? sourceArtist;
  final String? sourceAlbum;
  final String? sourceCoverUrl;
  final String? sourceIsrc;

  const DownloadInfo({
    required this.url,
    this.format,
    this.codec,
    this.bitDepth,
    this.sampleRate,
    this.quality,
    this.sourceTitle,
    this.sourceArtist,
    this.sourceAlbum,
    this.sourceCoverUrl,
    this.sourceIsrc,
  });

  @override
  String toString() =>
      'DownloadInfo(url: $url, format: $format, codec: $codec, bitDepth: $bitDepth, sampleRate: $sampleRate, quality: $quality, sourceTitle: $sourceTitle, sourceArtist: $sourceArtist)';
}
