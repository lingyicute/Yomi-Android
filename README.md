![Screenshot](https://github.com/lingyicute/yomi-android/blob/main/assets/icon.png?raw=true)

[Yomi](https://yomi.92li.uk) is an open source, nonprofit and cute [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev). The goal of the app is to create an easy to use instant messenger which is open source and accessible for everyone.

### Links:

- 🌐 [[Weblate] Translate Yomi into your language](https://hosted.weblate.org/projects/yomi/)
- 🌍 [[m] Join the community](https://matrix.to/#/#yomi:matrix.org)
- 📰 [[Mastodon] Get updates on social media](https://troet.cafe/@krille)
- 🖥️ [[Famedly] Server hosting and professional support](https://famedly.com/kontakt)
- 💝 [[Liberapay] Support Yomi development](https://de.liberapay.com/KrilleChritzelius)

<a href='https://ko-fi.com/C1C86VN53' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

### Screenshots:

![Screenshot](https://github.com/lingyicute/yomi-android/blob/main/docs/screenshots/product.jpeg?raw=true)

# Features

- 📩 Send all kinds of messages, images and files
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🌙 Dark mode
- 🎨 Material You design
- 📟 Hides complexity of Matrix IDs behind simple QR codes
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔄 Compatible with Element, Nheko, NeoChat and all other Matrix apps
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 😀 Emoji verification & cross signing

... and much more.


## Android background delivery

Android builds do not use Firebase Cloud Messaging. After a user signs in, Yomi starts a visible `dataSync` foreground service and performs an authenticated Matrix sync every 20 seconds. This is the Android-supported way to keep delivery working on devices without Google Play services; the persistent “Background connection is active” notification is expected.

For reliable delivery on aggressive Android variants, users should allow notifications and exclude Yomi from the vendor's battery optimisation settings. The service is restored after device reboot and stops itself when no account is logged in.

# Installation

Please visit the website for installation instructions:

- https://yomi.92li.uk

# How to build

Please visit the [Wiki](https://github.com/lingyicute/yomi-android/wiki) for build instructions:

- https://github.com/lingyicute/yomi-android/wiki/How-To-Build


# Special thanks

* <a href="https://github.com/fabiyamada">Fabiyamada</a> is a graphics designer and has made the yomi logo and the banner. Big thanks for her great designs.

* <a href="https://github.com/advocatux">Advocatux</a> has made the Spanish translation with great love and care. He always stands by my side and supports my work with great commitment.

* Thanks to MTRNord and Sorunome for developing.

* Also thanks to all translators and testers! With your help, yomi is now available in more than 12 languages.

* <a href="https://github.com/madsrh/WoodenBeaver">WoodenBeaver</a> sound theme for the notification sound.

* The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0
