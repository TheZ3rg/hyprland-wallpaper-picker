import QtQuick
import Quickshell

/*
   Entry point for a standalone picker process, loaded by `qs -p <project>`.

   The picker is the only child of ShellRoot, so quitting it ends the process
   and closes the overlay.
 */
ShellRoot {
    WallpaperPicker {}
}
