import QtQuick
import Quickshell

/*
   Entry point for a standalone picker process.

   `qs -p <project dir>` (and scripts/open-picker.sh) loads this file.
   ShellRoot is Quickshell's application root: everything inside it belongs to
   this one `qs` process. The picker is the only child, so quitting the process
   closes the overlay.
 */
ShellRoot {
    WallpaperPicker {}
}
