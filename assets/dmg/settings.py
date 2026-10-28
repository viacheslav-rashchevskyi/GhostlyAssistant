# dmgbuild layout for the GhostlyAssistant installer window.
# Used by scripts/make-dmg.sh:
#   dmgbuild -s assets/dmg/settings.py -D app=<.app> -D background=<.tiff> "GhostlyAssistant" <out.dmg>
import os.path

app = defines["app"]  # noqa: F821 — both provided by dmgbuild -D

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

# The background is 660x400 (1x and 2x in one TIFF); the arrow sits between these two icon centres.
background = defines["background"]  # noqa: F821
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (490, 190),
}

window_rect = ((200, 160), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
arrange_by = None
hide_extensions = [os.path.basename(app)]
