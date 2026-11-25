import QtQuick
import QtMultimedia

/**
 * Live video playback for the centered tile.
 *
 * Kept in its own file so the QtMultimedia import is loaded only when a video
 * card is centered. Systems without the QtMultimedia QML module keep the
 * static preview and the rest of the picker works.
 */
Item {
    id: root

    // File URL of the video to play.
    property url source

    // Position to seek to once the media is loaded, in milliseconds.
    property int seekMs: 0

    property bool seeked: false

    MediaPlayer {
        id: player

        source: root.source
        videoOutput: surface
        audioOutput: AudioOutput { muted: true }
        loops: MediaPlayer.Infinite
        autoPlay: false

        onSourceChanged: root.seeked = false

        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.LoadedMedia
                    && mediaStatus !== MediaPlayer.BufferedMedia)
                return;
            if (!root.seeked) {
                root.seeked = true;
                position = Math.max(0, root.seekMs);
            }
            play();
        }
    }

    VideoOutput {
        id: surface

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: player.playbackState === MediaPlayer.PlayingState
            && player.hasVideo
    }
}
