# dmgbuild settings for the drag-to-Applications window.
# Used by Tools/package.sh:  dmgbuild -s Tools/dmg-settings.py -D app=... "ASCII Sharks" out.dmg
import os

app = defines["app"]  # noqa: F821  (provided by dmgbuild)
background = defines.get("background")  # noqa: F821
appname = os.path.basename(app)

format = "ULFO"
filesystem = "HFS+"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volume_icon")  # noqa: F821
badge_icon = None

# The window: 660 x 420 points, icons on the art's two slots.
window_rect = ((200, 160), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {appname: (170, 210), "Applications": (490, 210)}
if not (background and os.path.exists(background)):
    background = "builtin-arrow"
arrange_by = None
include_icon_view_settings = True
