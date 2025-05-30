#!/usr/bin/env bash

# generate a temporary signing key adn apply its configuration
cd android
KEYFILE="$(pwd)/key.jks"
echo "Generating signing configuration with $KEYFILE..."
keytool -genkey -keyalg RSA -alias key -keysize 4096 -dname "cn=Yomi CI, ou=Head of bad integration tests, o=Yomi HQ, c=TLH" -keypass YOMI -storepass YOMI -validity 1 -keystore "$KEYFILE" -storetype "pkcs12"
echo "storePassword=YOMI" >> key.properties
echo "keyPassword=YOMI" >> key.properties
echo "keyAlias=key" >> key.properties
echo "storeFile=$KEYFILE" >> key.properties
ls | grep key
cd ..

# build release mode APK
flutter pub get
flutter build apk --release

# install and launch APK
flutter install
adb shell am start -n chat.lyi.yomi/chat.lyi.yomi.MainActivity

sleep 5

# check whether Yomi runs
adb shell ps | awk '{print $9}' | grep chat.lyi.yomi
