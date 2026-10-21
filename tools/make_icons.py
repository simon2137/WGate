"""Generate the Material-style icons the UI needs as 24dp SVGs.

The reference app draws everything with Material Icons; HarmonyOS has no
Material icon font, so the silhouettes are rebuilt here as single-colour SVGs
that can be tinted with Image.fillColor().
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), '..',
                   'entry', 'src', 'main', 'resources', 'base', 'media')
os.makedirs(OUT, exist_ok=True)

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
        'viewBox="0 0 24 24">')


def write(name, body):
    path = os.path.join(OUT, name + '.svg')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(HEAD + body + '</svg>\n')
    print('wrote', name, os.path.getsize(path))


def solid(d):
    return f'<path d="{d}" fill="#FF000000"/>'


def ring(d):
    return f'<path d="{d}" fill="#FF000000" fill-rule="evenodd"/>'


# --- home: roof triangle over a body; outlined variant is the same silhouette
# with a slab cut out of the middle.
write('ic_home', solid('M12 3 3 10.2V21h6.4v-6.6h5.2V21H21V10.2z'))
write('ic_home_filled', solid('M12 2.6 2.4 10.4V21.4h7.9v-6.4h3.4v6.4h7.9V10.4z'))

# --- bolt
write('ic_bolt', ring('M13.4 2 5.2 13.6h5.3L10.6 22l8.2-11.6h-5.3z'))
write('ic_bolt_filled', solid('M13.4 2 5.2 13.6h5.3L10.6 22l8.2-11.6h-5.3z'))

# --- cog: eight teeth around a ring, plus the hub hole.
def gear():
    cy = cx = 12.0
    teeth = 8
    r_out = 11.0
    r_in = 8.2
    half = 0.19  # half angular width of a tooth, as a fraction of the pitch
    pts = []
    pitch = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * pitch
        for sign in (-1, 1):
            ang = a + sign * half * pitch
            pts.append((cx + r_out * math.cos(ang), cy + r_out * math.sin(ang)))
        # valley between this tooth and the next
        for sign in (-1, 1):
            ang = a + pitch / 2 + sign * half * pitch * 0.75
            pts.append((cx + r_in * math.cos(ang), cy + r_in * math.sin(ang)))
    d = 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + ' Z'
    hole = 'M12 8.4a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2z'
    return d + ' ' + hole


write('ic_cog', ring(gear()))
write('ic_cog_filled', ring(gear()))

# --- question mark in a circle
write('ic_question',
      ring('M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16z') +
      solid('M12.7 6.4c-1.9 0-3.2 1.1-3.4 2.9h1.9c.1-.8.6-1.3 1.5-1.3.8 0 1.4.4 1.4 1.1 '
            '0 .6-.3 1-1.1 1.6-.9.6-1.2 1.2-1.2 2.2v.4h1.8v-.3c0-.6.2-.9.9-1.4 1-.7 1.5-1.4 '
            '1.5-2.6 0-1.6-1.3-2.6-3.3-2.6z') +
      solid('M11.9 15.3a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4z'))
write('ic_question_filled',
      solid('M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm.7 13.8a1.35 1.35 0 1 1 0 2.7 '
            '1.35 1.35 0 0 1 0-2.7zm.1-2.1v.2h-1.9v-.4c0-1 .3-1.6 1.2-2.2.8-.6 1.1-1 '
            '1.1-1.6 0-.7-.6-1.1-1.4-1.1-.9 0-1.4.5-1.5 1.3H8.4c.2-1.8 1.5-2.9 3.4-2.9 '
            '2 0 3.3 1 3.3 2.6 0 1.2-.5 1.9-1.5 2.6-.7.5-.9.8-.9 1.4z'))

# --- plus (add tunnel)
write('ic_add', solid('M11 4.5h2v6.5H19.5v2H13v6.5h-2V13H4.5v-2H11z'))

# --- reorder: two columns of dots / the standard "drag" glyph is three lines
write('ic_reorder', solid('M4 6.5h16v2H4zm0 4.5h16v2H4zm0 4.5h16v2H4z'))
write('ic_close', solid('M6.4 5 12 10.6 17.6 5 19 6.4 13.4 12 19 17.6 17.6 19 12 13.4 '
                        '6.4 19 5 17.6 10.6 12 5 6.4z'))
write('ic_chevron_down', solid('M7.4 9.4 12 14l4.6-4.6 1.4 1.4-6 6-6-6z'))
write('ic_chevron_up', solid('M7.4 14.6 12 10l4.6 4.6 1.4-1.4-6-6-6 6z'))
write('ic_arrow_down', solid('M11 4h2v12.2l3.6-3.6 1.4 1.4-6 6-6-6 1.4-1.4 3.6 3.6z'))
write('ic_arrow_up', solid('M11 20h2V7.8l3.6 3.6 1.4-1.4-6-6-6 6 1.4 1.4L11 7.8z'))
write('ic_back', solid('M15.4 5 16.8 6.4 11.2 12l5.6 5.6-1.4 1.4L8.4 12z'))
# --- top-bar actions of the configuration screen. The reference renders
# `Icons.Outlined.MoreVert`, `Icons.Outlined.Edit` and `Icons.Outlined.RemoveRedEye`
# there, so the paths are lifted from the Material set rather than drawn here.
write('ic_more', solid('M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 '
                       '2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z'))
write('ic_edit', solid('M14.06 9.02l.92.92L5.92 19H5v-.92l9.06-9.06M17.66 3c-.25 0-.51.1-.7.29l-1.83 1.83 3.75 '
                      '3.75 1.83-1.83c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.2-.2-.45-.29-.71-.29zm-3.6 3.19L3 17.25V21h3.75'
                      'L17.81 9.94l-3.75-3.75z'))
write('ic_remove_red_eye', solid('M12 6.5c3.79 0 7.17 2.13 8.82 5.5-1.65 3.37-5.02 5.5-8.82 5.5S4.83 15.37 3.18 '
                                '12C4.83 8.63 8.21 6.5 12 6.5m0-2C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 '
                                '11-7.5c-1.73-4.39-6-7.5-11-7.5zm0 5c1.38 0 2.5 1.12 2.5 2.5s-1.12 2.5-2.5 2.5-2.5-1.12'
                                '-2.5-2.5 1.12-2.5 2.5-2.5m0-2c-2.48 0-4.5 2.02-4.5 4.5s2.02 4.5 4.5 4.5 4.5-2.02 4.5-4.5'
                                '-2.02-4.5-4.5-4.5z'))

# --- document (configuration)
write('ic_doc', solid('M6 2h7.5L19 7.5V22H6zM13 3.2V8h4.6z'))
# --- star, twice: outline and filled
def star(inner=0.42, outer=1.0, cx=12.0, cy=12.2, r=9.4):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = r * (outer if i % 2 == 0 else inner)
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + ' Z'


write('ic_star', ring(star() + 'M12 6.9l1.4 3.4 3.7.3-2.8 2.4.9 3.6-3.2-1.9-3.2 1.9.9-3.6-2.8-2.4 3.7-.3z'))
write('ic_star_filled', solid(star()))
# --- route (multihop)
write('ic_route',
      solid('M6 3a2.6 2.6 0 1 1 0 5.2A2.6 2.6 0 0 1 6 3zm12 12.8a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z') +
      solid('M6.2 8.4h1.6v3.2c0 1.2 1 2.2 2.2 2.2h3.6v1.6H10c-2.1 0-3.8-1.7-3.8-3.8z'))
# --- split tunnelling (fork)
write('ic_split',
      solid('M6 4.2a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4zm12 0a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z'
            'M5.2 8.4h1.6v3.4c0 1.3 1 2.4 2.4 2.4h5.6c1.3 0 2.4-1.1 2.4-2.4V8.4h1.6v3.4c0 2.2-1.8 4-4 4H9.2c-2.2 0-4-1.8-4-4z') +
      solid('M11.2 14.6h1.6V21h-1.6z'))
# --- globe (IPv6 settings, the active-network row; path from the reference's
#     own res/drawable/globe.xml, 960-viewport rewritten onto 24 by
#     tools/svg_symbols_to_24.py with a zero y offset)
write('ic_globe',
      solid('M12 22q-2.075 0-3.9-0.788T4.925 19.075q-1.35-1.35-2.138-3.175T2 12q0-2.075 0.788-3.9'
            'T4.925 4.925q1.35-1.35 3.175-2.138T12 2q2.075 0 3.9 0.788T19.075 4.925q1.35 1.35 2.138 3.175'
            'T22 12q0 2.075-0.788 3.9T19.075 19.075q-1.35 1.35-3.175 2.138T12 22Z'
            'M12 20q3.35 0 5.675-2.325t2.325-5.675q0-0.175-0.013-0.363T19.975 11.325q-0.125 0.725-0.675 1.2'
            't-1.3 0.475h-2q-0.825 0-1.413-0.588T14 11v-1L10 10v-2q0-0.825 0.588-1.413T12 6h1q0-0.575 0.312-1.012'
            'T14.075 4.275q-0.5-0.125-1.012-0.2t-1.062-0.075q-3.35 0-5.675 2.325t-2.325 5.675h5q1.65 0 2.825 1.175'
            't1.175 2.825v1L10 17v2.75q0.5 0.125 0.988 0.188T12 20Z'))
# --- wifi (the reference's Icons.Outlined.Wifi)
write('ic_wifi',
      solid('M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3a4.237 4.237 0 0 0-6 0z'
            'm-4-4l2 2a7.074 7.074 0 0 1 10 0l2-2C15.14 9.14 8.87 9.14 5 13z'))
# --- info / check circle (the reference's Icons.Outlined.Info and CheckCircle,
#     used by the Auto-tunnel running row when it is off / on). Built as an
#     even-odd ring plus separate solid strokes, so the result does not depend
#     on sub-path winding.
write('ic_info',
      ring('M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z'
           'M12 20c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z') +
      solid('M11 11h2v6h-2zM11 7h2v2h-2z'))
write('ic_check_circle',
      ring('M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z'
           'M12 20c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z') +
      solid('M16.59 7.58L10 14.17l-2.59-2.58L6 13l4 4 8-8z'))
# --- metered mobile data (the reference's Icons.Outlined.SignalCellular4Bar)
write('ic_signal_cellular', solid('M2 22h20V2L2 22z'))
# --- ethernet (the reference's Icons.Outlined.SettingsEthernet)
write('ic_settings_ethernet',
      solid('M7.77 6.76 6.23 5.48.82 12l5.41 6.52 1.54-1.28L3.42 12l4.35-5.24zM7 13h2v-2H7v2zm10-2h-2v2h2v-2z'
            'm-6 2h2v-2h-2v2zm6.77-7.52-1.54 1.28L20.58 12l-4.35 5.24 1.54 1.28L23.18 12l-5.41-6.52z'))
# --- stop on no network (the reference's Icons.Outlined.PublicOff)
write('ic_public_off',
      solid('M11 8.17 6.49 3.66A9.91 9.91 0 0 1 12 2c5.52 0 10 4.48 10 10 0 2.04-.61 3.93-1.66 5.51l-1.46-1.46'
            'A7.842 7.842 0 0 0 20 12c0-3.35-2.07-6.22-5-7.41V5c0 1.1-.9 2-2 2h-2v1.17zm10.19 13.02-1.41 1.41'
            '-2.27-2.27A9.839 9.839 0 0 1 12 22C6.48 22 2 17.52 2 12c0-2.04.61-3.93 1.66-5.51L1.39 4.22 2.8 2.81'
            'l18.39 18.38zM11 18c-1.1 0-2-.9-2-2v-1l-4.79-4.79C4.08 10.79 4 11.38 4 12c0 4.08 3.05 7.44 7 7.93V18z'))
# --- data usage (metered)
write('ic_data', solid('M4.5 13h3.6V21H4.5zM10.2 8.6h3.6V21h-3.6zM15.9 4h3.6v17h-3.6z'))
# --- dns (server)
write('ic_dns',
      ring('M3.4 4.6h17.2v6.2H3.4zm1.8 1.8v2.6h6.4V6.4zM3.4 13.2h17.2v6.2H3.4zm1.8 1.8v2.6h6.4v-2.6z') +
      solid('M16.2 6.8a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4zm0 6.8a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z'))

# --- selection and groups
write('ic_circle', ring('M12 3.2a8.8 8.8 0 1 0 0 17.6A8.8 8.8 0 0 0 12 3.2zm0 1.8a7 7 0 1 1 0 14 7 7 0 0 1 0-14z'))
write('ic_folder', solid('M3 5h6.4l2 2H21v12H3z'))
write('ic_folder_open', solid('M3 5h6.4l2 2H21v2H7.6L4.8 19H3zM8.6 9.6H22l-2.8 9.4H4.8z'))
write('ic_delete',
      ring('M9 2h6v2h5v2H4V4h5zM6 7h12l-1 15H7z'))

# --- settings rows: the six glyphs `ui/screens/settings/SettingsScreen.kt`
# draws with Material Icons (Dns and Public already exist as ic_dns/ic_globe).
# Path data lifted from google/material-design-icons so the silhouettes match.
write('ic_autorenew',  # Icons.Outlined.Autorenew, tunnel recovery
      solid('M12 6v3l4-4-4-4v3c-4.42 0-8 3.58-8 8 0 1.57.46 3.03 1.24 4.26L6.7 14.8'
            'c-.45-.83-.7-1.79-.7-2.8 0-3.31 2.69-6 6-6zm6.76 1.74L17.3 9.2c.44.84.7 1.79.7 2.8'
            ' 0 3.31-2.69 6-6 6v-3l-4 4 4 4v-3c4.42 0 8-3.58 8-8 0-1.57-.46-3.03-1.24-4.26z'))
write('ic_view_quilt',  # Icons.AutoMirrored.Outlined.ViewQuilt, appearance
      solid('M21 5v6.5H9.33V5H21zM14.67 19v-6.5H9.33V19h5.34zM15.67 12.5V19H21v-6.5h-5.33z'
            'M8.33 19V5H3v14h5.33z'))
write('ic_security',  # Icons.Outlined.Security, security: the outlined shield
      ring('M12 1 3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z'
           'M12 3.1 4.9 6.4v4.6c0 4.6 3.2 8.7 7.1 9.8 3.9-1.1 7.1-5.2 7.1-9.8V6.4z'))
write('ic_view_headline',  # Icons.Outlined.ViewHeadline, local logging
      solid('M4 15h16v-2H4v2zm0 4h16v-2H4v2zm0-8h16V9H4v2zm0-6v2h16V5H4z'))
write('ic_backup_restore',  # Icons.Outlined.SettingsBackupRestore, backup and restore
      solid('M14 12a2 2 0 1 0-4 0 2 2 0 0 0 4 0zm-2-9c-4.97 0-9 4.03-9 9H0l4 4 4-4H5'
            'c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.51 0-2.91-.49-4.06-1.3l-1.42 1.44'
            'C8.04 20.3 9.94 21 12 21c4.97 0 9-4.03 9-9s-4.03-9-9-9z'))
# MonitorHeart only ships in the Material Symbols set, whose canvas is 960x960
# with y running from -960 to 0. `tools/svg_symbols_to_24.py` bakes that mapping
# (x/40, (y+960)/40) into the path data, so no <g transform> is needed here --
# ArkUI's SVG subset is the safest with plain 24-unit path data.
write('ic_monitor_heart',  # Icons.Outlined.MonitorHeart, tunnel monitoring
      solid('M2 9v-3q0 -0.825 0.588 -1.413T4 4h16q0.825 0 1.413 0.588T22 6v3h-2v-3H4v3H2Z'
            ' m2 11q-0.825 0 -1.413 -0.588T2 18v-3h2v3h16v-3h2v3q0 0.825 -0.588 1.413T20 20H4Z'
            ' m6 -3q0.275 0 0.525 -0.138t0.375 -0.413l3.1 -6.2 1.1 2.2q0.125 0.275 0.375 0.413'
            't0.525 0.138h6v-2H16.625l-1.725 -3.45q-0.125 -0.275 -0.375 -0.388t-0.525 -0.113'
            'q-0.275 0 -0.525 0.113T13.1 7.55L10 13.75l-1.1 -2.2q-0.125 -0.275 -0.375 -0.413'
            't-0.525 -0.138H2v2h5.375l1.725 3.45q0.125 0.275 0.375 0.413t0.525 0.138Z'))

# --- detail pages: `settings/recovery`, `settings/security` and the backup
# sheet draw these with Material Icons (Timer, ScreenLockPortrait, Pin, Restore)
# plus the reference's own `drawable/database` vector for the backup row.
write('ic_timer',  # Icons.Outlined.Timer, seamless recovery delay
      '<rect x="9" y="1" width="6" height="2" fill="#FF000000"/>' +
      solid('M19.03 7.39l1.42-1.42c-.43-.51-.9-.99-1.41-1.41l-1.42 1.42C16.07 4.74 14.12 4 12 4'
            'c-4.97 0-9 4.03-9 9 0 4.97 4.02 9 9 9s9-4.03 9-9c0-1.12-.74-3.07-1.97-4.61z'
            'M13 14h-2V8h2v6z'))
write('ic_screen_lock',  # Icons.Outlined.ScreenLockPortrait, screen recording protection
      solid('M10 16h4c.55 0 1-.45 1-1v-3c0-.55-.45-1-1-1v-1c0-1.11-.9-2-2-2-1.11 0-2 .9-2 2v1'
            'c-.55 0-1 .45-1 1v3c0 .55.45 1 1 1zm.8-6c0-.66.54-1.2 1.2-1.2.66 0 1.2.54 1.2 1.2v1'
            'h-2.4v-1zM17 1H7c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3'
            'c0-1.1-.9-2-2-2zm0 18H7V5h10v14z'))
write('ic_pin',  # Icons.Outlined.Pin (a push pin), app lock
      solid('M16 9V4h1c.55 0 1-.45 1-1s-.45-1-1-1H7c-.55 0-1 .45-1 1s.45 1 1 1h1v5'
            'c0 1.66-1.34 3-3 3v2h5.97v7l1 1 1-1v-7H19v-2c-1.66 0-3-1.34-3-3z'))
write('ic_restore',  # Icons.Outlined.Restore, restore from a backup
      solid('M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7'
            's7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42'
            'C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21'
            '-3.5-2.08V8H12z'))
write('ic_database',  # the reference's drawable/database, backup application data
      solid('M12 21q-3.775 0 -6.388 -1.163T3 17v-10q0 -1.65 2.638 -2.825T12 3q3.725 0 6.363 1.175'
            'T21 7v10q0 1.675 -2.613 2.838T12 21Z'
            ' M12 9.025q2.225 0 4.475 -0.638T19 7.025q-0.275 -0.725 -2.513 -1.375T12 5'
            'q-2.275 0 -4.463 0.638T5 7.025q0.35 0.75 2.538 1.375T12 9.025Z'
            ' M12 14q1.05 0 2.025 -0.1t1.863 -0.288q0.888 -0.188 1.675 -0.463t1.438 -0.625v-3'
            'q-0.65 0.35 -1.438 0.625t-1.675 0.463Q15 10.8 14.025 10.9t-2.025 0.1'
            'q-1.05 0 -2.05 -0.1t-1.888 -0.288Q7.175 10.425 6.4 10.15t-1.4 -0.625v3'
            'q0.625 0.35 1.4 0.625t1.663 0.463Q8.95 13.8 9.95 13.9t2.05 0.1Z'
            ' M12 19q1.15 0 2.337 -0.175t2.188 -0.463q1 -0.288 1.675 -0.65t0.8 -0.738v-2.45'
            'q-0.65 0.35 -1.438 0.625t-1.675 0.463Q15 15.8 14.025 15.9t-2.025 0.1'
            'q-1.05 0 -2.05 -0.1t-1.888 -0.288Q7.175 15.425 6.4 15.15t-1.4 -0.625v2.475'
            'q0.125 0.375 0.788 0.725t1.663 0.638q1 0.288 2.2 0.463t2.35 0.175Z'))

# --- notifications page: NotificationsActive, AltRoute, SwapVert, Replay and
# WarningAmber from the same Material set.
write('ic_notifications_active',
      solid('M7.58 4.08 6.15 2.65C3.75 4.48 2.17 7.3 2.03 10.5h2c.15-2.65 1.51-4.97 3.55-6.42z'
            'm12.39 6.42h2c-.15-3.2-1.73-6.02-4.12-7.85l-1.42 1.43c2.02 1.45 3.39 3.77 3.54 6.42z'
            'M18 11c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68'
            'C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2v-5zm-6 11c.14 0 .27-.01.4-.04'
            '.65-.14 1.18-.58 1.44-1.18.1-.24.15-.5.15-.78h-4c.01 1.1.9 2 2.01 2z'))
write('ic_alt_route',
      solid('M9.78 11.16l-1.42 1.42c-.68-.69-1.34-1.58-1.79-2.94l1.94-.49'
            'c.32.89.77 1.5 1.27 2.01zM11 6 7 2 3 6h3.02c.02.81.08 1.54.19 2.17l1.94-.49'
            'C8.08 7.2 8.03 6.63 8.02 6H11zM21 6l-4-4-4 4h2.99c-.1 3.68-1.28 4.75-2.54 5.88'
            '-.5.44-1.01.92-1.45 1.55-.34-.49-.73-.88-1.13-1.24L9.46 13.6C10.39 14.45 11 15.14 11 17'
            'v5h2v-5c0-2.02.71-2.66 1.79-3.63 1.38-1.24 3.08-2.78 3.2-7.37H21z'))
write('ic_swap_vert',
      solid('M16 17.01V10h-2v7.01h-3L15 21l4-3.99h-3zM9 3 5 6.99h3V14h2V6.99h3L9 3z'))
write('ic_replay',
      solid('M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4'
            'c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z'))
write('ic_warning_amber',
      solid('M12 5.99 19.53 19H4.47L12 5.99M12 2 1 21h22L12 2z'
            'M11 16h2v2h-2zM11 10h2v5h-2z'))

# --- the save action: `Icons.Rounded.Save`, which the reference app puts in the
# top bar of every settings screen that has pending edits (DNS, proxy, tunnel
# configuration) as an icon button, not as the word "Save".
write('ic_save',
      solid('M17.59 3.59c-.38-.38-.89-.59-1.42-.59H5c-1.11 0-2 .9-2 2v14c0 1.1.9 2 2 2h14'
            'c1.1 0 2-.9 2-2V7.83c0-.53-.21-1.04-.59-1.41l-2.82-2.83z'
            'M12 19c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3z'
            'm1-10H7c-1.1 0-2-.9-2-2s.9-2 2-2h6c1.1 0 2 .9 2 2s-.9 2-2 2z'))

