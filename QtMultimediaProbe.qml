import QtQuick
import QtMultimedia

/**
 * Loaded only to detect whether the QtMultimedia QML module is installed.
 *
 * It draws nothing and creates no player; WallpaperStrip checks the Loader
 * status instead of showing this item.
 */
Item {}
