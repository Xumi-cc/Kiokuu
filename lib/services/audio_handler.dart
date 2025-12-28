import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';

class MediaKitAudioHandler extends BaseAudioHandler with SeekHandler {
  Player _activePlayer;
  List<StreamSubscription> _playerSubscriptions = [];

  MediaKitAudioHandler(this._activePlayer) {
    _setupPlayerListeners(_activePlayer);
  }

  /// Update which player the audio service tracks for notification bar state.
  /// Call this when switching between main player and prefetch player.
  void setActivePlayer(Player player) {
    if (player == _activePlayer) return;

    // Cancel existing subscriptions
    for (var sub in _playerSubscriptions) {
      sub.cancel();
    }
    _playerSubscriptions.clear();

    _activePlayer = player;
    _setupPlayerListeners(player);
  }

  void _setupPlayerListeners(Player player) {
    // Listen to player state and update audio_service
    _playerSubscriptions.add(
      player.stream.playing.listen((playing) {
        playbackState.add(
          playbackState.value.copyWith(
            playing: playing,
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.skipToNext,
            ],
            androidCompactActionIndices: const [0, 1, 2],
            processingState: AudioProcessingState.ready,
          ),
        );
      }),
    );

    _playerSubscriptions.add(
      player.stream.position.listen((position) {
        playbackState.add(
          playbackState.value.copyWith(updatePosition: position),
        );
      }),
    );

    _playerSubscriptions.add(
      player.stream.duration.listen((duration) {
        if (duration != Duration.zero) {
          mediaItem.add(mediaItem.value?.copyWith(duration: duration));
        }
      }),
    );
  }

  // Callbacks to be set by MusicProvider
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration)? onSeek;

  @override
  Future<void> play() async => await onPlay?.call();

  @override
  Future<void> pause() async => await onPause?.call();

  @override
  Future<void> skipToNext() async => await onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => await onSkipToPrevious?.call();

  @override
  Future<void> seek(Duration position) async => await onSeek?.call(position);

  void updateNowPlaying({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    String? artworkPath,
  }) {
    mediaItem.add(
      MediaItem(
        id: title,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: artworkPath != null
            ? (artworkPath.startsWith('http')
                  ? Uri.parse(artworkPath)
                  : Uri.file(artworkPath))
            : null,
      ),
    );
  }
}

Future<MediaKitAudioHandler> initAudioService(Player player) async {
  return await AudioService.init(
    builder: () => MediaKitAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.kiokuu.channel.audio',
      androidNotificationChannelName: 'KioKuu',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    ),
  );
}
