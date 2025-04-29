# Ubiquiti Wireshark Dissectors

These are a collection of Wireshark dissectors, including decryption, for:

1. Syslog messages on UDP port 5514
2. INFORM messages on HTTP port 8080
3. Discovery messages on UDP port 10001

# Decryption

Decryption requires either Wireshark 4.5 (untested) or that you install [luagcrypt](https://github.com/Lekensteyn/luagcrypt).

## Key Files

Unifi devices encrypt syslog and INFORM messages using a device-specific key.
Use the
[`get-inform-key.sh`](get-inform-key.sh)
[`get-syslog-key.sh`](get-syslog-key.sh)
scripts to retrieve these from the devices that use SSH.
There may be better ways of doing this.

This might work in a pinch (adjust as needed):

```sh
HOSTS=$(seq -f '192.168.1.%g' -s ' ' 10 23) USER=$USERNAME make ui-inform-keys.txt ui-syslog-keys.sh
```

The dissectors will look for these files in the current working directory, but this can be configured
in the Wireshark preferences (INFORM and UISYSLOG protocols).

# Field List

```
inform.decompressed
inform.decrypted
inform.field.cfgversion
inform.field.hostname
inform.field.ipv4
inform.field.ipv6
inform.field.isolated
inform.field.mac
inform.field.model
inform.field.model_disp
inform.field.serial
inform.field.server_time
inform.field.time
inform.field.uptime
inform.field.version
inform.flags
inform.flags.encrypted
inform.flags.gcm
inform.flags.snappy
inform.flags.zlib
inform.gcm.aad
inform.gcm.ciphertext
inform.gcm.tag
inform.iv
inform.json
inform.mac
inform.magic
inform.payload
inform.payload_length
inform.payload_version
inform.version

uidisc.field.default
uidisc.field.dhcp_client
uidisc.field.dhcp_client_bound
uidisc.field.essid
uidisc.field.firmware_version
uidisc.field.interface.addr
uidisc.field.interface.config
uidisc.field.interface.mac
uidisc.field.interface.name
uidisc.field.ip
uidisc.field.length
uidisc.field.locating
uidisc.field.mac
uidisc.field.mac
uidisc.field.model
uidisc.field.name
uidisc.field.network.ip
uidisc.field.network.mac
uidisc.field.network_version
uidisc.field.platform
uidisc.field.primary.ip
uidisc.field.primary.mac
uidisc.field.req_version
uidisc.field.sshd_port
uidisc.field.type
uidisc.field.type20.f2
uidisc.field.type20.f3
uidisc.field.type20.f4
uidisc.field.type20.f5
uidisc.field.type20.mac
uidisc.field.ui_direct_hostname
uidisc.field.unknown
uidisc.field.unparsed
uidisc.field.uptime
uidisc.field.username
uidisc.field.wmode
uidisc.length
uidisc.type
uidisc.version

uisyslog.gcm.aad
uisyslog.gcm.ciphertext
uisyslog.gcm.iv
uisyslog.gcm.tag
uisyslog.hashid
uisyslog.line
uisyslog.magic
uisyslog.unknown
uisyslog.version
```

# `jsond.lua`

This is a library that decodes JSON while retaining the TvbRange, so that JSON-derived fields can
maintain their link back to the original bytes.
