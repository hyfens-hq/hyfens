# Waypoint demo assets

All SVG illustrations in `images/waypoint/` are original local vector artwork
created for this repository. They contain no Mobbin or third-party app assets,
logos, screenshots, or copied branding.

`fonts/InterVariable.ttf` is the Inter variable font, downloaded from the
official Inter repository at the immutable commit
`e3a3d4c57d5ecc01453a575621882a384c1995a3`:

`https://raw.githubusercontent.com/rsms/inter/e3a3d4c57d5ecc01453a575621882a384c1995a3/docs/font-files/InterVariable.ttf`

The accompanying `fonts/Inter-OFL.txt` is the repository's `LICENSE.txt` at
the same commit. The font is licensed under the SIL Open Font License 1.1 by
The Inter Project Authors. The font download command and SHA-256 are recorded
in the task validation output.

`video/waypoint-route-preview.mp4` is a deterministic, silent abstract route
scene generated locally with FFmpeg's built-in `color` and `drawbox` filters.
It is not remote media or third-party footage. The exact generation command is:

```sh
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0xC7E6EA:s=640x360:r=24:d=3,drawbox=x=0:y=0:w=640:h=360:color=0xC7E6EA@1:t=fill,drawbox=x=0:y=220:w=640:h=140:color=0x1B5B6B@1:t=fill,drawbox=x=0:y=186:w=640:h=34:color=0x81B69D@1:t=fill,drawbox=x='mod(76+128*t,760)-116':y=214:w=116:h=10:color=0xF5B85B@1:t=fill,drawbox=x='mod(470-62*t,700)-40':y=130:w=40:h=22:color=0xFFF4D8@1:t=fill,drawbox=x=90:y='250+18*sin(2*PI*t/3)':w=460:h=4:color=0xF6DB9A@1:t=fill,drawbox=x=32:y=30:w=204:h=44:color=0x173F55@0.86:t=fill" -an -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -movflags +faststart assets/video/waypoint-route-preview.mp4
```

The JSON files in `data/` are hand-authored, deterministic local mock payloads
for the Waypoint demo. They do not contain credentials or remote URLs.
