## 0.4.1 - smallbug fixes, including better option parsing

## 0.4 - fix system browser call with shellwords.escape
Also tell user when bookmarks cannot be found instead of hanging.

## 0.3.2 - ACTUALLY (hopefully) fix nil string search issue
The persistent null string error came from not having a search engine
configured properly by default. This has been updated. Also, a :browse option
is specified in case users want to open up chrome bookmarks in some other
browser, the default from 'xdg-open'.

## 0.3.1 - fix nil string search issue
