# frozen_string_literal: true

# builds the github pages site into site/:
#
#   site/index.html            readme.md, rendered
#   site/assets/               the screencast the readme embeds
#   site/coverage/             the simplecov html report, copied wholesale
#   site/badge-coverage.json   shields.io endpoint, read by the readme badge
#
# run it with `just docs`, which produces the coverage report first. the
# workflow in .github/workflows/pages.yml runs the same recipe, so what deploys
# on a merge to main is what you can look at locally before pushing.

require "fileutils"
require "json"
require "kramdown"
require "kramdown-parser-gfm"

ROOT = File.expand_path("..", __dir__)
SITE = File.join(ROOT, "site")
COVERAGE = File.join(ROOT, "coverage")

# github renders these in the readme; kramdown has no idea what they are, and
# would leave the bare `:bookmark:` text sitting in a heading
EMOJI = {":bookmark:" => "🔖"}.freeze

def readme_html
  markdown = File.read(File.join(ROOT, "readme.md"))
  EMOJI.each { |code, char| markdown = markdown.gsub(code, char) }
  # GFM rather than kramdown's own dialect, so the page matches what github
  # shows for the same file - hard_wrap off, since the readme wraps its prose
  # at 80 columns and every one of those would otherwise become a <br>
  Kramdown::Document.new(markdown, input: "GFM", hard_wrap: false, auto_ids: true).to_html
end

# the report is what the coverage link points at, so a missing one is a broken
# page rather than a smaller one - say so instead of deploying the hole
def copy_coverage
  unless File.exist?(File.join(COVERAGE, "index.html"))
    abort "no coverage report at #{COVERAGE} - run `just cov` first"
  end

  dest = File.join(SITE, "coverage")
  FileUtils.mkdir_p(dest)

  # .resultset.json and friends are simplecov's own scratch state, and they
  # carry absolute paths from whatever machine ran the suite. the report does
  # not read them, so they have no business on a public page
  Dir.glob("*", base: COVERAGE).each do |entry|
    FileUtils.cp_r(File.join(COVERAGE, entry), File.join(dest, entry))
  end
end

# shields.io endpoint badge: the readme points an <img> at this file's url on
# the deployed site, so the badge tracks whatever main last measured
def write_badge
  last_run = File.join(COVERAGE, ".last_run.json")
  percent = JSON.parse(File.read(last_run)).dig("result", "line")
  abort "no line coverage in #{last_run}" if percent.nil?

  color = if percent >= 100 then "brightgreen"
  elsif percent >= 90 then "green"
  elsif percent >= 75 then "yellow"
  else "red"
  end

  File.write(
    File.join(SITE, "badge-coverage.json"),
    JSON.generate(
      schemaVersion: 1,
      label: "coverage",
      message: "#{format("%g", percent)}%",
      color: color
    )
  )
end

def page(body)
  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>booker - a CLI bookmark manager</title>
    <meta name="description" content="Search, browse, and open Chrome, Firefox, and Safari bookmarks from the command line.">
    <style>#{stylesheet}</style>
    </head>
    <body>
    <nav>
      <a href="https://github.com/jeremywrnr/booker">github</a>
      <a href="https://rubygems.org/gems/booker">rubygems</a>
      <a href="coverage/">coverage</a>
    </nav>
    <main>#{body}</main>
    </body>
    </html>
  HTML
end

# no build step and no external stylesheet: one <style> block, and a palette
# that follows the reader's system theme the way the simplecov report does
def stylesheet
  <<~CSS
    :root {
      --bg: #fff; --fg: #24292f; --muted: #57606a;
      --link: #0969da; --border: #d0d7de; --code-bg: #f6f8fa;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117; --fg: #e6edf3; --muted: #8b949e;
        --link: #4493f8; --border: #30363d; --code-bg: #161b22;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 0 1.25rem 4rem; background: var(--bg); color: var(--fg);
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    }
    nav {
      display: flex; gap: 1.25rem; max-width: 46rem; margin: 0 auto;
      padding: 1rem 0; border-bottom: 1px solid var(--border);
    }
    nav a { color: var(--muted); text-decoration: none; font-size: .9rem; }
    nav a:hover { color: var(--link); }
    main { max-width: 46rem; margin: 0 auto; }
    a { color: var(--link); }
    h1, h2, h3, h4, h5 { line-height: 1.25; margin: 2rem 0 1rem; }
    h1 { font-size: 2rem; }
    h2 { font-size: 1.5rem; padding-bottom: .3rem; border-bottom: 1px solid var(--border); }
    h5 { font-size: 1rem; color: var(--muted); }
    img { max-width: 100%; }
    code {
      background: var(--code-bg); border-radius: 6px; padding: .15em .4em;
      font: .875em/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    pre {
      background: var(--code-bg); border-radius: 6px; padding: 1rem;
      overflow-x: auto; border: 1px solid var(--border);
    }
    pre code { background: none; padding: 0; }
  CSS
end

FileUtils.rm_rf(SITE)
FileUtils.mkdir_p(SITE)

File.write(File.join(SITE, "index.html"), page(readme_html))
FileUtils.cp_r(File.join(ROOT, "assets"), File.join(SITE, "assets"))
copy_coverage
write_badge

puts "built site/ (#{Dir.glob("#{SITE}/**/*").count { |f| File.file?(f) }} files)"
