# booker - search, browse and open browser bookmarks from the command line
#
# Load order matters in one place: Bookmarks::PARSER_SOURCE names the parser
# classes while its class body runs, so parsers has to come first.

require_relative "booker/version"
require_relative "booker/output"
require_relative "booker/config"
require_relative "booker/parsers"
require_relative "booker/bookmarks"
require_relative "booker/installer"
require_relative "booker/cli"

module Booker
end
