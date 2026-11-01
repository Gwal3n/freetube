# FreeTube for iOS

A native, account-free YouTube client for iPhone. Browse and search videos, follow channels locally, and keep your history, playlists, and downloads on your device. The project takes inspiration from [NewPipe](https://github.com/TeamNewPipe/NewPipe).

## Build and install

Open `FreeTube/FreeTube.xcodeproj` in Xcode and build with your own signing team. The **Build unsigned IPA** GitHub Actions workflow also produces an unsigned IPA. It must be signed before it can be installed on an iPhone.

The app targets iOS 17 or later. YouTube can change the interfaces this app relies on, so playback and downloads may occasionally need updates.

## Origins

This is a fork of [leshkodev/freetube](https://github.com/leshkodev/freetube). It uses [b5i/YouTubeKit](https://github.com/b5i/YouTubeKit) for YouTube data and a [modified copy of alexeichhorn/YouTubeKit](Vendor/FreeTubeStreamKit/UPSTREAM.md) for stream extraction. Download support also uses [yt-dlp](https://github.com/yt-dlp/yt-dlp) through [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS).

The app is independent of YouTube, Google, and NewPipe. Its source is available under the [MIT license](LICENSE), which retains the original author's copyright notice. See [third-party software](THIRD_PARTY.md) for the components used by the app.
