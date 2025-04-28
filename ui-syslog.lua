set_plugin_info({
    version = "0.0.1",
    description = "Ubiquiti Syslog Dissector",
    author = "David Nesting",
    repository = "https://github.com/dnesting/ui-dissector",
})

local gcrypt_ok, gcrypt = pcall(require, "luagcrypt")
if not gcrypt_ok then
    gcrypt = nil
end

local ui_syslog_proto = Proto("UISYSLOG", "Ubiquiti Syslog Protocol")

-- fields
local fields = {
    magic         = ProtoField.uint32("uisyslog.magic", "Magic", base.HEX),
    version       = ProtoField.uint8("uisyslog.version", "Version", base.DEC),
    unknown       = ProtoField.uint8("uisyslog.unknown", "Unknown", base.DEC),
    device_hashid = ProtoField.bytes("uisyslog.hashid", "Device HashID"),
    iv            = ProtoField.bytes("uisyslog.iv", "GCM IV"),
    aad           = ProtoField.bytes("uisyslog.aad", "GCM AAD"),
    ciphertext    = ProtoField.bytes("uisyslog.ciphertext", "Ciphertext"),
    tag           = ProtoField.bytes("uisyslog.tag", "GCM Tag"),
    plain         = ProtoField.string("uisyslog.plain", "Decrypted Line", base.ASCII),
}
ui_syslog_proto.fields = fields

-- pull link-layer source MAC
local f_eth_src = Field.new("eth.src")

ui_syslog_proto.prefs.keys_file = Pref.string("Key File", "ui-syslog-keys.txt",
    "Path to syslog device keys file (format <MAC> <HEX_KEY>)")

local syslog_keys = {}

function ui_syslog_proto.init()
    -- Clear existing
    syslog_keys = {}

    -- Try to load from configured file
    local filename = ui_syslog_proto.prefs.keys_file
    if filename and filename ~= "" then
        local file = io.open(filename, "r")
        if file then
            for line in file:lines() do
                local mac, hexkey = line:match("(%S+)%s+(%S+)")
                if mac and hexkey then
                    syslog_keys[mac:lower()] = ByteArray.new(hexkey):raw()
                end
            end
            file:close()
        else
            print("[inform] Could not open keys file:", filename)
        end
    end
    -- print("[inform] Loaded keys for", tablelength(device_keys), "devices")
end

local function get_syslog_key(mac_addr_tvb)
    return syslog_keys[tostring(mac_addr_tvb):lower()] or nil
end

local function decrypt_gcm(key, iv, ciphertext, ad, tag)
    local aes = gcrypt.Cipher(gcrypt.CIPHER_AES256, gcrypt.CIPHER_MODE_GCM)
    aes:setkey(key)
    aes:setiv(iv)
    aes:authenticate(ad)
    local plaintext = aes:decrypt(ciphertext)

    local ok, err = pcall(function()
        aes:checktag(tag)
    end)

    return plaintext, ok, err
end

function is_printable(s)
    for i = 1, #s do
        local byte = string.byte(s, i)
        if byte > 127 then
            return false
        elseif byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
            return false
        end
    end
    return true
end

function ui_syslog_proto.dissector(buf, pinfo, tree)
    if buf:len() < 40 or buf(0, 4):uint() ~= 0xABCDDCBA then return end
    pinfo.cols.protocol = ui_syslog_proto.name

    local st = tree:add(ui_syslog_proto, buf(), "Ubiquiti Syslog")
    st:add(fields.magic, buf(0, 4))
    st:add(fields.version, buf(4, 1))
    st:add(fields.unknown, buf(5, 4))
    st:add(fields.device_hashid, buf(9, 8))

    local iv         = buf(17, 12)
    local aad        = buf(0, 29)
    local ctext_len  = buf:len() - 29 - 16
    local ciphertext = buf(29, ctext_len)
    local tag        = buf(buf:len() - 16, 16)

    local est        = st:add("AES‐256‐GCM")
    est:add(fields.iv, iv)
    est:add(fields.aad, aad)
    est:add(fields.ciphertext, ciphertext)
    est:add(fields.tag, tag)

    -- extract sender MAC
    local eth_src_fv = f_eth_src()
    local mac_addr   = eth_src_fv and tostring(eth_src_fv) or "<unknown>"

    local key        = get_syslog_key(mac_addr)
    if not key then
        st:add_expert_info(PI_DECRYPTION, PI_INFO,
            "No key for device MAC " .. mac_addr)
        return
    end

    local plain, ok, err = decrypt_gcm(key,
        iv:raw(),
        ciphertext:raw(),
        aad:raw(),
        tag:raw())
    if not ok then
        st:add_expert_info(PI_DECRYPTION, PI_WARN,
            "AES‐GCM failed: " .. err)
        return
    end

    local dec = ByteArray.new(plain, true):tvb("Decrypted Line")
    st:add(fields.plain, dec())

    local dec_str = dec():raw()
    if is_printable(dec_str) then
        pinfo.cols.info:append(" " .. dec_str)
    end

    -- try to decode dec with the syslog dissector
    local syslog_proto = Dissector.get("syslog")
    if syslog_proto then
        syslog_proto:call(dec, pinfo, tree)
    else
        st:add_expert_info(PI_PROTOCOL, PI_WARN,
            "No syslog dissector found")
    end
end

local tbl = DissectorTable.get("udp.port")
tbl:add(5514, ui_syslog_proto)
