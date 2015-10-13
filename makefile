v=0.1

build:
	gem build booker.gemspec
	gem install ./booker-$(v).gem

clean:
	rm booker-$(v).gem

push: clean build
	gem push booker-$(v)

find:
	@echo seaching for chrome bookmarks json...
	@find ~ -iname '*bookmarks' | grep -i chrom
