#!/usr/bin/env ruby
# Manual smoke test for SafariBookmarkParser.
# Usage: ruby bin/test_safari.rb [search_term]
#
# Requires Full Disk Access for your terminal app (System Settings →
# Privacy & Security → Full Disk Access) so plutil can read the plist.

require "json"
require_relative "../lib/bookmarks"

search = ARGV[0] || "olympics"
plist = ENV["HOME"] + "/Library/Safari/Bookmarks.plist"

unless File.exist?(plist)
  puts "FAIL: ".red + "Safari bookmarks file not found at #{plist}"
  exit 1
end

puts "Searching Safari bookmarks for: ".cyan + search
puts "Source: ".cyan + plist
puts

parser = SafariBookmarkParser.new(plist, search)
parser.parse
results = parser.results

if results.empty?
  puts "FAIL: ".red + "no matches for '#{search}'"
  puts "Hint: ".yel + "verify Full Disk Access, or try a different term"
  exit 1
end

puts "PASS: ".grn + "#{results.length} match(es) found"
puts
results.each do |b|
  puts "  folder: #{b.folder}"
  puts "  title:  #{b.title}"
  puts "  url:    #{b.url}"
  puts "  id:     #{b.id}"
  puts
end
