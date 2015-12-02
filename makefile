v=0.4.1

build:
	gem build booker.gemspec
	gem install ./booker-$(v).gem

clean:
	rm -v *.gem

push: clean build
	gem push booker-$(v).gem

dev:
	filewatcher '**/*' 'clear && rake'

find:
	@echo seaching for chrome bookmarks json...
	@find ~ -iname '*bookmarks' | grep -i chrom
