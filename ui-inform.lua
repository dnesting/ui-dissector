set_plugin_info({
    version = "0.0.1",
    description = "Ubiquiti INFORM Message Dissector",
    author = "David Nesting",
    repository = "https://github.com/dnesting/ui-dissector",
})

local gcrypt_ok, gcrypt = pcall(require, "luagcrypt")
if not gcrypt_ok then
    gcrypt = nil
end
local json_ok, json = pcall(require, "jsond")
if not json_ok then
    json = nil
end

local ui_inform_proto = Proto("INFORM", "Ubiquiti INFORM Message")

-- fields
local fields = {
    magic             = ProtoField.string("inform.magic", "Magic"),
    version           = ProtoField.uint32("inform.version", "Version", base.DEC),
    mac               = ProtoField.ether("inform.mac", "Hardware Address"),
    flags             = ProtoField.uint16("inform.flags", "Flags", base.HEX),
    flag_encrypted    = ProtoField.bool("inform.flags.encrypted", "Encrypted", 16, nil, 0x01),
    flag_zlib         = ProtoField.bool("inform.flags.zlib", "ZLib Compressed", 16, nil, 0x02),
    flag_snappy       = ProtoField.bool("inform.flags.snappy", "Snappy Compressed", 16, nil, 0x04),
    flag_gcm          = ProtoField.bool("inform.flags.gcm", "AES-GCM", 16, nil, 0x08),
    iv                = ProtoField.bytes("inform.iv", "Initialization Vector"),
    payload_version   = ProtoField.uint32("inform.payload_version", "Payload Version", base.DEC),
    payload_length    = ProtoField.uint32("inform.payload_length", "Payload Length", base.DEC),
    payload_raw       = ProtoField.bytes("inform.payload", "Raw Payload"),
    gcm_aad           = ProtoField.bytes("inform.gcm.aad", "GCM AAD"),
    gcm_ciphertext    = ProtoField.bytes("inform.gcm.ciphertext", "GCM Ciphertext"),
    gcm_tag           = ProtoField.bytes("inform.gcm.tag", "GCM Tag"),

    field_ipv6        = ProtoField.ipv6("inform.field.ipv6", "IPv6 Address"),
    field_ipv4        = ProtoField.ipv4("inform.field.ipv4", "IPv4 Address"),
    field_mac         = ProtoField.ether("inform.field.mac", "MAC Address"),
    field_serial      = ProtoField.string("inform.field.serial", "Serial Number"),
    field_time        = ProtoField.absolute_time("inform.field.time", "Time"),
    field_server_time = ProtoField.absolute_time("inform.field.server_time", "Server Time"),
    field_model       = ProtoField.string("inform.field.model", "Model"),
    field_model_disp  = ProtoField.string("inform.field.model_disp", "Display Model"),
    field_version     = ProtoField.string("inform.field.version", "Version"),
    field_uptime      = ProtoField.uint32("inform.field.uptime", "Uptime", base.DEC),
    field_hostname    = ProtoField.string("inform.field.hostname", "Hostname"),
    field_cfgversion  = ProtoField.string("inform.field.cfgversion", "Config Version"),
    field_isolated    = ProtoField.bool("inform.field.isolated", "Isolated"),
    decrypted         = ProtoField.bytes("inform.decrypted", "Decrypted Payload"),
    decompressed      = ProtoField.bytes("inform.decompressed", "Decompressed Payload"),
    json              = ProtoField.string("inform.json", "JSON Payload"),
}

ui_inform_proto.fields = fields

-- encryption keys
ui_inform_proto.prefs.keys_file = Pref.string("Key File", "ui-inform-keys.txt",
    "Path to INFORM device keys file (format <MAC> <HEX_KEY>)")

-- local function tablelength(T)
--   local count = 0
--   for _ in pairs(T) do count = count + 1 end
--   return count
-- end

local inform_keys = {}

function ui_inform_proto.init()
    -- Clear existing
    inform_keys = {}

    -- Try to load from configured file
    local filename = ui_inform_proto.prefs.keys_file
    if filename and filename ~= "" then
        local file = io.open(filename, "r")
        if file then
            for line in file:lines() do
                local mac, hexkey = line:match("(%S+)%s+(%S+)")
                if mac and hexkey then
                    -- strip : from mac
                    mac = mac:gsub(":", "")
                    inform_keys[mac:lower()] = ByteArray.new(hexkey):raw()
                end
            end
            file:close()
        else
            print("[inform] Could not open keys file:", filename)
        end
    end
    -- print("[inform] Loaded keys for", tablelength(device_keys), "devices")
end

local function get_inform_key(mac_addr_tvb)
    return inform_keys[tostring(mac_addr_tvb):lower()] or nil
end

local function decrypt_cbc(key, iv, ciphertext)
    local aes = gcrypt.Cipher(gcrypt.CIPHER_AES128, gcrypt.CIPHER_MODE_CBC)
    aes:setkey(key)
    aes:setiv(iv)
    local plaintext = aes:decrypt(ciphertext)
    return plaintext
end

local function decrypt_gcm(key, iv, ciphertext, ad, tag)
    local aes = gcrypt.Cipher(gcrypt.CIPHER_AES128, gcrypt.CIPHER_MODE_GCM)
    aes:setkey(key)
    aes:setiv(iv)
    aes:authenticate(ad)
    local plaintext = aes:decrypt(ciphertext)

    local ok, err = pcall(function()
        aes:checktag(tag)
    end)

    return plaintext, ok, err
end

local function md5(data)
    local md = gcrypt.Hash(gcrypt.MD_MD5)
    md:write(data)
    return md:read()
end

local default_key = md5("ubnt")

function ui_inform_proto.dissector(buf, pinfo, tree)
    if buf:len() < 40 then
        return
    end

    if buf(0, 4):string() ~= "TNBU" then
        return
    end

    pinfo.cols.protocol = ui_inform_proto.name
    local subtree = tree:add(ui_inform_proto, buf(), "Ubiquiti INFORM Message")
    subtree:add(fields.magic, buf(0, 4))
    subtree:add(fields.version, buf(4, 4))
    local mac = buf(8, 6)
    subtree:add(fields.mac, mac)

    subtree:add(fields.flags, buf(14, 2))
    subtree:add(fields.flag_encrypted, buf(14, 2))
    subtree:add(fields.flag_zlib, buf(14, 2))
    subtree:add(fields.flag_snappy, buf(14, 2))
    subtree:add(fields.flag_gcm, buf(14, 2))

    local flags = buf(14, 2):uint()
    local iv = buf(16, 16)
    subtree:add(fields.iv, iv)
    subtree:add(fields.payload_version, buf(32, 4))
    local payload_version = buf(32, 4):uint()
    subtree:add(fields.payload_length, buf(36, 4))
    local payload_length = buf(36, 4):uint()

    if buf:len() < 40 + payload_length then
        subtree:add_expert_info(PI_MALFORMED, PI_ERROR, "packet shorter than declared payload")
        --return
    end

    local payload = buf(40, payload_length)
    subtree:add(fields.payload_raw, payload)

    if (flags & 0x01) ~= 0 then
        -- encrypted
        if not gcrypt then
            subtree:add_expert_info(PI_DECRYPTION, PI_INFO, "decrypt: luagcrypt not installed")
            return
        end

        -- key is AES-128
        local key = get_inform_key(mac)
        local used_default = false
        if not key then
            key = default_key
            used_default = true
        end

        local dec
        if (flags & 0x08) ~= 0 then
            -- AES128-GCM
            local ciphertext = payload(0, payload_length - 16)
            local aad = buf(0, 40)
            local tag = payload(payload_length - 16, 16)

            local gcm_tree = subtree:add("GCM Authentication Info")
            gcm_tree:add(fields.gcm_ciphertext, ciphertext)
            gcm_tree:add(fields.gcm_aad, aad)
            gcm_tree:add(fields.gcm_tag, tag)

            local valid, err
            dec, valid, err = decrypt_gcm(key, iv:raw(), ciphertext:raw(), aad:raw(), tag:raw())
            if not valid then
                if used_default then
                    subtree:add_expert_info(PI_DECRYPTION, PI_WARN,
                        "decrypt: no key found for " ..
                        mac:bytes():tohex(true, ":") ..
                        " in file " .. ui_inform_proto.prefs.keys_file .. ", will try with md5('ubnt')")
                else
                    subtree:add_expert_info(PI_DECRYPTION, PI_WARN, "decrypt: " .. err)
                end
            end
        else
            -- AES128-CBC
            dec = decrypt_cbc(key, iv:raw(), payload:raw())
        end

        dec = ByteArray.new(dec, true):tvb("Decrypted Payload")
        payload = dec
        subtree:add(fields.decrypted, payload())
    end

    if (flags & 0x06) ~= 0 then
        -- compressed
        local dec
        if (flags & 0x02) ~= 0 then
            dec = payload():uncompress_zlib("Uncompressed Payload")
        else
            dec = payload():uncompress_snappy("Uncompressed Payload")
        end
        if dec then
            payload = dec:tvb("Uncompressed Payload")
            subtree:add(fields.decompressed, payload())
        else
            subtree:add_expert_info(PI_MALFORMED, PI_WARN, "uncompress failed")
            return
        end
    end

    if payload_version == 1 and payload(0, 1):string() == "{" then
        subtree:add(fields.json, payload())
        if json then
            local inst = json.decode(payload)
            if inst then
                local jtree = subtree -- subtree:add("Fields")
                if inst["hostname"] then jtree:add(fields.field_hostname, inst["hostname"]()) end
                if inst["model"] then jtree:add(fields.field_model, inst["model"]()) end
                if inst["model_display"] then jtree:add(fields.field_model_disp, inst["model_display"]()) end
                if inst["serial"] then jtree:add(fields.field_serial, inst["serial"]()) end
                if inst["version"] then jtree:add(fields.field_version, inst["version"]()) end
                if inst["cfgversion"] then jtree:add(fields.field_cfgversion, inst["cfgversion"]()) end
                if inst["mac"] then jtree:add(fields.field_mac, inst["mac"]:ether()) end
                if inst["ip"] then jtree:add(fields.field_ipv4, inst["ip"]:ipv4()) end
                if inst["ipv6"] then
                    for i, v in ipairs(inst["ipv6"]) do
                        jtree:add(fields.field_ipv6, v:ipv6())
                    end
                end
                if inst["uptime"] then jtree:add(fields.field_uptime, inst["uptime"]()) end
                if inst["time"] then
                    jtree:add(fields.field_time, inst["time"]:time())
                end
                if inst["server_time_in_utc"] then
                    local stime = inst["server_time_in_utc"]
                    if json.type(stime) == "string" then
                        stime = stime:number()
                    end
                    if json.type(stime) == "number" then
                        jtree:add(fields.field_server_time, stime:time())
                    else
                        jtree:add_expert_info(PI_MALFORMED, PI_WARN,
                            "server_time_in_utc is not a number")
                    end
                end
                if inst["isolated"] ~= nil then
                    jtree:add(fields.field_isolated, inst["isolated"]())
                end

                if inst["model"] or inst["model_display"] or inst["hostname"] or inst["isolated"] then
                    pinfo.cols.info:append(", INFORM(")
                    local started = false
                    if inst["model_display"] or inst["model"] then
                        pinfo.cols.info:append(tostring(inst["model_display"] or inst["model"]))
                        started = true
                    end
                    if inst["hostname"] then
                        if started then
                            pinfo.cols.info:append(", ")
                        end
                        pinfo.cols.info:append(tostring(inst["hostname"]))
                        started = true
                    end
                    if inst["isolated"] and inst["isolated"]:val() then
                        if started then
                            pinfo.cols.info:append(", ")
                        end
                        pinfo.cols.info:append("Isolated")
                    end
                    pinfo.cols.info:append(")")
                end
            end
        end
        local jd = Dissector.get("json")
        if jd then
            jd:call(payload, pinfo, tree)
        end
    end
end

local tbl = DissectorTable.get("media_type")
tbl:add("application/x-binary", ui_inform_proto)
