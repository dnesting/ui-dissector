test: 
	lua test/test_json_de.lua
.PHONY: test

all: json.lua ui-inform-keys.txt ui-syslog-keys.txt

json.lua:
	curl -o $@ https://raw.githubusercontent.com/rxi/json.lua/11077824d7cfcd28a4b2f152518036b295e7e4ce/json.lua

ui-inform-keys.txt:
	for h in $(HOSTS); do sh get-inform-key.sh $(USER)@$$h; done >$@

ui-syslog-keys.txt:
	for h in $(HOSTS); do sh get-syslog-key.sh $(USER)@$$h; done >$@
