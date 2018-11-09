## 0.6.1 one command installation process

## 0.6 faster bookmark search, better versioning

## 0.5 merge make into rake, mark for improvements

## 0.4.1 - small bug fixes, including better option parsing

## 0.4 - fix system browser call with shellwords.escape
Also tell user when bookmarks cannot be found instead of hanging.

## 0.3.2 - ACTUALLY fix nil string search issue
The persistent null string error came from not having a search engine
configured properly by default. This has been updated. Also, a :browse option
is specified in case users want to open up chrome bookmarks in some other
browser, the default from 'xdg-open'.

## 0.3.1 - fix nil string search issue
