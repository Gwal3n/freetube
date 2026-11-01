# Third-party software

This app builds on the following projects. Their licenses and copyright notices remain with their respective sources.

- [FreeTube for iOS by Leshko](https://github.com/leshkodev/freetube), the original app. Its copyright notice remains in this repository's [MIT license](LICENSE).
- [NewPipe](https://github.com/TeamNewPipe/NewPipe), design and feature inspiration. NewPipe code is not included here.
- [b5i/YouTubeKit](https://github.com/b5i/YouTubeKit) and the [vendored alexeichhorn/YouTubeKit fork](Vendor/FreeTubeStreamKit/UPSTREAM.md), for metadata and stream extraction. The vendored fork retains its [MIT license](Vendor/FreeTubeStreamKit/LICENSE).
- [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS) and [yt-dlp](https://github.com/yt-dlp/yt-dlp), used by the download pipeline.
- [Kingfisher](https://github.com/onevcat/Kingfisher) and [SwimplyPlayIndicator](https://github.com/obrhoff/SwimplyPlayIndicator), used by the interface.
- [FFmpeg-iOS-Support](https://github.com/kewlbear/FFmpeg-iOS-Support) and its FFmpeg binaries, used to assemble downloaded media. FFmpeg's license obligations depend on the exact binary configuration; verify and include the matching notices and source information with any distributed IPA.
- The bundled Mozilla certificate bundle has its [source and attribution](FreeTube/FreeTube/Resources/cacert-SOURCE.md) and [license](FreeTube/FreeTube/Resources/cacert-LICENSE.txt) in the repository.

Before distributing a signed build, check the exact resolved dependencies and bundled binaries, and provide the license notices they require alongside the download.
