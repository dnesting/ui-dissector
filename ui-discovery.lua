set_plugin_info({
    version = "0.0.1",
    description = "Ubiquiti Discovery Protocol",
    author = "David Nesting",
    repository = "https://github.com/dnesting/ui-dissector",
})

local ui_discovery_proto = Proto("UIDISC", "Ubiquiti Discovery Protocol UIDISC")

local field = {
    version      = ProtoField.uint8("uidisc.version", "Version", base.DEC),
    type         = ProtoField.uint8("uidisc.type", "Type", base.HEX),
    length       = ProtoField.uint16("uidisc.length", "Length", base.DEC),

    field_type   = ProtoField.uint8("uidisc.field.type", "Type", base.HEX),
    field_length = ProtoField.uint16("uidisc.field.length", "Field length", base.DEC),
    -- the rest will be populated below
}

local handlers = {}

-- track some information for the UI
local label_model
local label_name
local label_platform

-- 0x01
field.field_hw_address = ProtoField.ether("uidisc.field.mac", "MAC Address")
handlers[0x01] = function(buf, st, annotate)
    local mac_r = buf(0, 6)
    annotate("Hardware Address", mac_r:ether())
    st:add(field.field_hw_address, mac_r)
end

-- 0x02
field.field_network_ether = ProtoField.ether("uidisc.field.network.mac", "MAC Address")
field.field_network_ip = ProtoField.ipv4("uidisc.field.network.ip", "IP Address")
handlers[0x02] = function(buf, st, annotate)
    local mac_r = buf(0, 6)
    local ip_r = buf(6, 4)
    annotate("Network Address", tostring(mac_r:ether()) .. " / " .. tostring(ip_r:ipv4()))
    st:add(field.field_network_ether, mac_r)
    st:add(field.field_network_ip, ip_r)
end

-- 0x03
field.field_firmversion = ProtoField.string("uidisc.field.firmware_version", "Firmware Version")
handlers[0x03] = function(buf, st, annotate)
    annotate("Firmware Version", buf():string())
    st:add(field.field_firmversion, buf())
end

-- 0x04
field.field_ip = ProtoField.ipv4("uidisc.field.ip", "IP Address")
handlers[0x04] = function(buf, st, annotate)
    annotate("IP Address", buf():ipv4())
    st:add(field.field_ip, buf())
end

-- 0x05
field.field_mac = ProtoField.ether("uidisc.field.mac", "MAC Address")
handlers[0x05] = function(buf, st, annotate)
    annotate("MAC Address", buf():ether())
    st:add(field.field_mac, buf())
end

-- 0x06
field.field_username = ProtoField.string("uidisc.field.username", "Username")
handlers[0x06] = function(buf, st, annotate)
    annotate("Username", buf():string())
    st:add(field.field_username, buf())
end

-- 0x0A
field.field_uptime = ProtoField.relative_time("uidisc.field.uptime", "Uptime")
handlers[0x0A] = function(buf, st, annotate)
    annotate("Uptime", buf:uint())
    st:add(field.field_uptime, buf(0, 4))
end

-- 0x0B
field.field_name = ProtoField.string("uidisc.field.name", "Name")
handlers[0x0B] = function(buf, st, annotate)
    annotate("Name", buf():string())
    if label_name == nil then
        label_name = buf():string()
    end
    st:add(field.field_name, buf())
end

-- 0x0C
field.field_platform = ProtoField.string("uidisc.field.platform", "Platform")
handlers[0x0C] = function(buf, st, annotate)
    annotate("Platform", buf():string())
    if label_platform == nil then
        label_platform = buf():string()
    end
    st:add(field.field_platform, buf())
end

-- 0x0D
field.field_essid = ProtoField.string("uidisc.field.essid", "ESSID")
handlers[0x0D] = function(buf, st, annotate)
    if buf:len() > 0 then
        annotate("ESSID", buf():string())
        st:add(field.field_essid, buf())
    else
        annotate("ESSID (empty)")
    end
end

-- 0x0E
field.field_wmode = ProtoField.uint8("uidisc.field.wmode", "WMode")
handlers[0x0E] = function(buf, st, annotate)
    annotate("WMode", buf(0, 1):uint())
    st:add(field.field_wmode, buf(0, 1))
end

-- 0x14
field.field_model = ProtoField.string("uidisc.field.model", "Model")
handlers[0x14] = function(buf, st, annotate)
    annotate("Model", buf():string())
    if label_model == nil then
        label_model = buf():string()
    end
    st:add(field.field_model, buf())
end

handlers[0x15] = handlers[0x14] -- ??
-- 0x16
field.field_network_version = ProtoField.string("uidisc.field.network_version", "Network Version")
handlers[0x16] = function(buf, st, annotate)
    annotate("Network Version", buf():string())
    st:add(field.field_network_version, buf())
end

-- 0x17
field.field_default = ProtoField.bool("uidisc.field.default", "Default")
handlers[0x17] = function(buf, st, annotate)
    annotate("Default", buf(0, 1):uint() == 1)
    st:add(field.field_default, buf(0, 1))
end

-- 0x18
field.field_locating = ProtoField.bool("uidisc.field.locating", "Locating")
handlers[0x18] = function(buf, st, annotate)
    annotate("Locating", buf(0, 1):uint() == 1)
    st:add(field.field_locating, buf(0, 1))
end

-- 0x19
field.field_dhcpclient = ProtoField.bool("uidisc.field.dhcp_client", "DHCP Client")
handlers[0x19] = function(buf, st, annotate)
    annotate("DHCP Client", buf(0, 1):uint() == 1)
    st:add(field.field_dhcpclient, buf(0, 1))
end

-- 0x1A
field.field_dhcpclientbound = ProtoField.bool("uidisc.field.dhcp_client_bound", "DHCP Client Bound")
handlers[0x1A] = function(buf, st, annotate)
    annotate("DHCP Client Bound", buf(0, 1):uint() == 1)
    st:add(field.field_dhcpclientbound, buf(0, 1))
end

-- 0x1B
field.field_reqversion = ProtoField.string("uidisc.field.req_version", "Required Firmware Version")
handlers[0x1B] = function(buf, st, annotate)
    annotate("Request Version", buf():string())
    st:add(field.field_reqversion, buf())
end

-- 0x1C
field.field_sshdport = ProtoField.uint16("uidisc.field.sshd_port", "SSHD Port", base.DEC)
handlers[0x1C] = function(buf, st, annotate)
    annotate("SSHD Port", buf(0, 2):uint())
    st:add(field.field_sshdport, buf(0, 2))
end

-- 0x20
field.field_type20_mac = ProtoField.ether("uidisc.field.type20.mac", "Type 20 MAC Address")
field.field_type20_f2 = ProtoField.uint64("uidisc.field.type20.f2", "Type 20 F2")
field.field_type20_f3 = ProtoField.uint64("uidisc.field.type20.f3", "Type 20 F3")
field.field_type20_f4 = ProtoField.absolute_time("uidisc.field.type20.f4", "Type 20 F4")
field.field_type20_f5 = ProtoField.uint64("uidisc.field.type20.f5", "Type 20 F5")
handlers[0x20] = function(buf, st, annotate)
    -- This is a string of the form "HEX:INT" where the HEX portion represents a few sub-fields:
    -- D8B370123456      - MAC Address
    -- 0000000001122EEF  - Unknown hex integer
    -- 0000000002233DDE  - Unknown hex integer
    -- 0000000067555555  - Unknown hex integer but suspiciously similar to a time_t
    -- :123456789        - Unknown integer after : separator (maybe fractional seconds?)

    local mac_r = buf(0, 12)
    local f2_r = buf(12, 16)
    local f3_r = buf(28, 16)
    local f4_r = buf(44, 16)
    -- skip colon
    local f5_r = buf(61, buf:len() - 61)

    local mac_addr = mac_r(0, 2):raw() ..
        ":" ..
        mac_r(2, 2):raw() ..
        ":" .. mac_r(4, 2):raw() .. ":" .. mac_r(6, 2):raw() .. ":" .. mac_r(8, 2):raw() .. ":" .. mac_r(10, 2):raw()
    st:add(field.field_type20_mac, mac_r, Address.ether(mac_addr))
    st:add(field.field_type20_f2, f2_r, ByteArray.new(f2_r:raw()):uint64())
    st:add(field.field_type20_f3, f3_r, ByteArray.new(f3_r:raw()):uint64())
    local f4_ts = NSTime(ByteArray.new(f4_r:raw()):uint64():tonumber(), 0)
    st:add(field.field_type20_f4, f4_r, f4_ts)
    st:add(field.field_type20_f5, f5_r, UInt64.new(tonumber(f5_r:raw())))
    annotate("Unknown (Possibly Firmware Build)")
end

-- 0x2F
field.field_primary_hw_address = ProtoField.ether("uidisc.field.primary.mac", "Primary MAC Address")
field.field_primary_ip = ProtoField.ipv4("uidisc.field.primary.ip", "Primary IP Address")
handlers[0x2F] = function(buf, st, annotate)
    local mac_r = buf(0, 6)
    local ip_r = buf(6, 4)
    annotate("Primary Address", tostring(mac_r:ether()) .. " / " .. tostring(ip_r:ipv4()))
    st:add(field.field_primary_hw_address, mac_r)
    st:add(field.field_primary_ip, ip_r)
end

-- 0x30
field.field_ui_direct_hostname = ProtoField.string("uidisc.field.ui_direct_hostname", "Hostname")
handlers[0x30] = function(buf, st, annotate)
    annotate("UI Direct Hostname", buf():string())
    st:add(field.field_ui_direct_hostname, buf())
end

-- 0x32
field.field_iface_mac = ProtoField.ether("uidisc.field.interface.mac", "Interface MAC Address")
field.field_iface_ip4 = ProtoField.ipv4("uidisc.field.interface.addr", "Interface IPv4 address")
field.field_iface_config = ProtoField.string("uidisc.field.interface.config", "Interface configuration")
field.field_iface_name = ProtoField.string("uidisc.field.interface.name", "Interface name")
handlers[0x32] = function(buf, st, annotate)
    annotate("Interface Configuration")
    st:add(field.field_iface_mac, buf(0, 6))
    st:add(field.field_iface_ip4, buf(6, 4))
    local payload = buf(10, buf:len() - 10)
    st:add(field.field_iface_config, payload)
    local json_ok, json = pcall(require, "jsond")
    if json_ok then
        local iface = json.decode(payload)
        if iface and iface.name then
            st:add(field.field_iface_name, iface.name())
            st:append_text(" (" .. tostring(iface.name) .. ")")
        end
    else
        st:add_expert_info(PI_UNDECODED, PI_CHAT, "json module not found, unable to decode interface configuration")
    end
end

-- unknown
field.field_unknown = ProtoField.bytes("uidisc.field.unknown", "Unknown Data")
local function default_handler(buf, st, annotate)
    -- Other unseen fields others have found
    -- 0x07 Salt
    -- 0x08 RndChallenge
    -- 0x09 Challenge
    -- 0x0F WebUI
    -- 0x12 Sequence
    -- 0x13 Serial
    -- 0x15 Model?
    annotate("Unknown")
    st:add(field.field_unknown, buf())
end

-- for errors later
field.field_unparsed_data = ProtoField.bytes("uidisc.field.unparsed", "Unparsed Data")

ui_discovery_proto.fields = field


local function add_field(buffer, subtree)
    local type_buf = buffer(0, 1)
    local type = type_buf:uint()
    local st = subtree:add(ui_discovery_proto, buffer(), tostring(type))
    local ft = st:add(field.field_type, type_buf)

    if buffer:len() < 3 then
        -- add a warning
        st:add_expert_info(PI_MALFORMED, PI_ERROR, "Truncated field (fragmentation not implemented yet)")
        st:add(field.field_unparsed_data, buffer())
        return buffer:len()
    end

    local len_buf = buffer(1, 2)
    local field_len = len_buf:uint()
    st:add(field.field_length, len_buf)

    if buffer:len() < field_len then
        st:add_expert_info(PI_MALFORMED, PI_ERROR, "Truncated field (fragmentation not implemented yet)")
        st:add(field.field_unparsed_data, buffer())
        return buffer:len()
    end

    local function annotate(label, value)
        st:append_text(": " .. label)
        if value ~= nil then
            st:append_text(" (" .. tostring(value) .. ")")
        end
        ft:append_text(" (" .. label .. ")")
    end

    local buf = buffer(3, field_len)
    local handler = handlers[type]
    if handler then
        handler(buf, st, annotate)
    else
        default_handler(buf, st, annotate)
    end
    return field_len + 3 -- 3 bytes for type and length
end


function ui_discovery_proto.dissector(buf, pinfo, tree)
    if buf:len() == 0 then return end
    pinfo.cols.protocol = ui_discovery_proto.name

    label_model = nil
    label_name = nil
    label_platform = nil

    local subtree = tree:add(ui_discovery_proto, buf(), "Ubiquiti Discovery Protocol")
    subtree:add(field.version, buf(0, 1))
    subtree:add(field.type, buf(1, 1))
    subtree:add(field.length, buf(2, 2))

    local offset = 4
    local len = buf:len()

    while offset < len do
        local field_len = add_field(buf(offset, len - offset), subtree)
        offset = offset + field_len
    end
    if label_model ~= nil then
        subtree:append_text(", Model: " .. label_model)
        pinfo.cols.info:append(" Model=" .. label_model)
    end
    if label_platform ~= nil then
        subtree:append_text(", Platform: " .. label_platform)
        if label_model == nil then
            pinfo.cols.info:append(" Platform=" .. label_platform)
        end
    end
    if label_name ~= nil then
        subtree:append_text(", Name: " .. label_name)
        pinfo.cols.info:append(" Name=" .. label_name)
    end
end

local tbl = DissectorTable.get("udp.port")
tbl:add(10001, ui_discovery_proto)
