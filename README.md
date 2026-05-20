# element-x-so-create

Builds FFmpeg 6.0 shared libraries for Android (4 ABIs) used by the
`CustomWithOwnFfmpeg` decoder path in element-x-android.

Produces:

- `libavcodec_own.so`
- `libavutil_own.so`
- `libswscale_own.so`
- `libswresample_own.so`

for each of `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`.

The `_own` suffix on each SONAME prevents collisions with the identically
named .so files NextLib ships in its AAR.

## How

Run the **Build FFmpeg for Android** workflow manually (Actions tab → Run workflow).
Artifacts are uploaded as `ffmpeg-android-libs-<run-number>.zip`. Download and
extract into `element-x-android/libraries/mediaviewer/impl/external/ffmpeg-own/`.

## Codec set

Minimal: H.264 + HEVC decode only. Audio decoders and demuxers disabled.

## License

FFmpeg n6.0 is LGPL-2.1+ (with some optional components GPL); the build script
keeps only LGPL components.