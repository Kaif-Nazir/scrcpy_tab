#!/bin/bash
set -ex

case "$1" in
    32)
        WINXX=win32
        ;;
    64)
        WINXX=win64
        ;;
    *)
        echo "ERROR: $0 must be called with one argument: 32 or 64" >&2
        exit 1
        ;;
esac

cd "$(dirname ${BASH_SOURCE[0]})"
. build_common
cd .. # root project dir

WINXX_BUILD_DIR="$WORK_DIR/build-$WINXX"

# Build dependencies
app/deps/adb_windows.sh
app/deps/sdl.sh $WINXX cross shared
app/deps/dav1d.sh $WINXX cross shared
app/deps/ffmpeg.sh $WINXX cross shared
app/deps/libusb.sh $WINXX cross shared

DEPS_INSTALL_DIR="$PWD/app/deps/work/install/$WINXX-cross-shared"
ADB_INSTALL_DIR="$PWD/app/deps/work/install/adb-windows"

# Ensure pkg-config finds the deps install, but preserve any PKG_CONFIG_PATH set by the workflow.
# Prepend our pkgconfig dir so tools find the cross .pc first.
export PKG_CONFIG_PATH="$DEPS_INSTALL_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:}$PKG_CONFIG_PATH"
export PKG_CONFIG_LIBDIR="$DEPS_INSTALL_DIR/lib/pkgconfig"

# Ensure the compiler searches common SDL include locations: include/, include/SDL3/, include/SDL/
# Adding -I for non-existent dirs is harmless and covers different SDL install layouts.
EXTRA_INCLUDE_ARGS="-I$DEPS_INSTALL_DIR/include -I$DEPS_INSTALL_DIR/include/SDL3 -I$DEPS_INSTALL_DIR/include/SDL"
EXTRA_LINK_ARGS="-L$DEPS_INSTALL_DIR/lib"

# Robustness: if SDL's CMake install didn't create a pkg-config file, create a minimal fallback sdl3.pc
mkdir -p "$DEPS_INSTALL_DIR/lib/pkgconfig"
if [ ! -f "$DEPS_INSTALL_DIR/lib/pkgconfig/sdl3.pc" ]; then
  cat > "$DEPS_INSTALL_DIR/lib/pkgconfig/sdl3.pc" <<'EOF'
prefix=@DEPS_INSTALL_DIR@
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: SDL3
Description: SDL3 library (fallback .pc created by CI)
Version: 3.4.8
Libs: -L${libdir} -lSDL3
Cflags: -I${includedir} -I${includedir}/SDL3 -I${includedir}/SDL
EOF
  sed -i "s|@DEPS_INSTALL_DIR@|$DEPS_INSTALL_DIR|g" "$DEPS_INSTALL_DIR/lib/pkgconfig/sdl3.pc"
fi

# Debug: show pkg-config files and SDL header layout (useful in CI logs)
echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
echo "Listing $DEPS_INSTALL_DIR/lib/pkgconfig:"
ls -la "$DEPS_INSTALL_DIR/lib/pkgconfig" || true
echo "Installed SDL headers:"
ls -la "$DEPS_INSTALL_DIR/include" || true
ls -la "$DEPS_INSTALL_DIR/include/SDL3" || true
ls -la "$DEPS_INSTALL_DIR/include/SDL" || true

# Ensure the compiler sees the deps include/lib dirs even if Meson doesn't get them
export CFLAGS="-I$DEPS_INSTALL_DIR/include -I$DEPS_INSTALL_DIR/include/SDL3 -I$DEPS_INSTALL_DIR/include/SDL ${CFLAGS:-}"
export CPPFLAGS="$CFLAGS ${CPPFLAGS:-}"
export LDFLAGS="-L$DEPS_INSTALL_DIR/lib ${LDFLAGS:-}"

# Configure and build
rm -rf "$WINXX_BUILD_DIR"
meson setup "$WINXX_BUILD_DIR" \
    --cross-file=cross_$WINXX.txt \
    --buildtype=release \
    --strip \
    -Db_lto=true \
    -Dcompile_server=false \
    -Dportable=true \
    -Dv4l2=false \
    "-Dc_args=$EXTRA_INCLUDE_ARGS" \
    "-Dc_link_args=$EXTRA_LINK_ARGS"

ninja -C "$WINXX_BUILD_DIR"

# Group intermediate outputs into a 'dist' directory
mkdir -p "$WINXX_BUILD_DIR/dist"
cp "$WINXX_BUILD_DIR"/app/scrcpy.exe "$WINXX_BUILD_DIR/dist/"
cp app/data/scrcpy-noconsole.vbs "$WINXX_BUILD_DIR/dist/"
cp app/data/scrcpy.png "$WINXX_BUILD_DIR/dist/"
cp app/data/disconnected.png "$WINXX_BUILD_DIR/dist/"
cp app/data/open_a_terminal_here.bat "$WINXX_BUILD_DIR/dist/"
cp "$DEPS_INSTALL_DIR"/bin/*.dll "$WINXX_BUILD_DIR/dist/" || true
cp -r "$ADB_INSTALL_DIR"/. "$WINXX_BUILD_DIR/dist/"
