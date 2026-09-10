# dmgbuild settings. Paths come from -D flags.

app = defines["app"]
background = defines["background"]
icon = defines.get("icon")

volume_name = "Mous"
format = "UDZO"

files = [app]
symlinks = {"Applications": "/Applications"}

window_rect = ((240, 160), (640, 380))
icon_size = 128
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
arrange_by = None

icon_locations = {
    "Mous.app": (160, 155),
    "Applications": (480, 155),
}

if icon:
    volume_icon = icon
