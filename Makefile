test: 
	lua test/test_json_de.lua

all: ui-inform-keys.txt ui-syslog-keys.txt

ui-inform-keys.txt:
	for h in $(HOSTS); do sh get-inform-key.sh $(USER)@$$h; done >$@

ui-syslog-keys.txt:
	for h in $(HOSTS); do sh get-syslog-key.sh $(USER)@$$h; done >$@

.PHONY: test all
