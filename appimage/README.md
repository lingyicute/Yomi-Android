# Yomi AppImage

Yomi is provided as AppImage too. To Download, visit yomi.im.

## Building

- Ensure you install `appimagetool`

```shell
flutter build linux

# copy binaries to appimage dir
cp -r build/linux/{x64,arm64}/release/bundle appimage/Yomi.AppDir
cd appimage

# prepare AppImage files
cp Yomi.desktop Yomi.AppDir/
mkdir -p Yomi.AppDir/usr/share/icons
cp ../assets/logo.svg Yomi.AppDir/yomi.svg
cp AppRun Yomi.AppDir

# build the AppImage
appimagetool Yomi.AppDir
```
