# Identity proposal

**Working name: Plyvia.** It is short, easy to say, and distinct from the upstream FreeTube name. It does not imply an official YouTube or NewPipe connection. The name is a proposal, not a completed trademark clearance.

The [icon concept](icon-concept.svg) uses a simple play mark inside a flowing P. Its dark, neutral palette suits the current player and works without borrowing YouTube's red play button or the upstream icon. The final icon should have light and tinted variants for iOS.

For a public release, change the display name, launch artwork, app icon, repository name, and unsigned IPA artifact together. Keep the upstream copyright and license notice, and identify the project as a fork in the README and About screen.

The current bundle identifier is `com.leshko.freetube`. Renaming the display name and icon can happen without changing it. A new identifier such as `io.github.gwal3n.plyvia` would make a separate app installation; existing local data and downloaded files would not move automatically. Export and restore covers settings and library records, but downloaded media needs its own migration plan. Decide on the identifier before publishing the first branded sideload build.
