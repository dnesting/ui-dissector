--
-- jsond.lua
--
-- Copyright (c) 2025 David Nesting
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local jsond = { _version = "0.0.1" }

local escape_char_map = {
  ["\\"] = "\\",
  ["\""] = "\"",
  ["\b"] = "b",
  ["\f"] = "f",
  ["\n"] = "n",
  ["\r"] = "r",
  ["\t"] = "t",
}

local escape_char_map_inv = { ["/"] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end

local function typename(obj)
  local mt = getmetatable(obj)
  if mt and mt.__name then
    return mt.__name
  end
  return type(obj)
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

function jsond.type(obj)
  if obj.__json_type then
    return obj.__json_type
  end
  if obj and obj.__get_json_type then
    return obj:__get_json_type()
  end
  error("type() called on non-Value object")
end

local Value = {}
Value.__index = Value
Value.__name = "Value"

function Value:new(value, range)
  if type(value) ~= "number" and type(value) ~= "nil" and type(value) ~= "boolean" then
    error("Value:new() expected number, nil or boolean, got " .. typename(value))
  end
  local obj = setmetatable({}, self)
  obj._range = range
  obj._val = value
  return obj
end

function Value:__get_json_type()
  local v = self:val()
  if type(v) == "number" then
    return "number"
  elseif type(v) == "boolean" then
    return "boolean"
  elseif v == nil then
    return "null"
  else
    error("Value:__get_json_type() called on non-Value object")
  end
end

function Value:__tostring() return tostring(self._val) end

function Value:__call() return self._range, self._val end

function Value:type() return jsond.type(self) end

function Value:val() return self._val end

function Value:range() return self._range end

function Value:time()
  local val = self:val()
  if type(val) == "number" then
    local secs, nsecs = math.modf(val)
    return self._range, NSTime.new(secs, nsecs * 1e9)
  end
  return nil
end

function Value:raw() return self._range:raw() end

local String = {}
String.__index = String
String.__name = "String"
String.__json_type = "string"
String.__tostring = Value.__tostring
String.__call = Value.__call
String.type = Value.type
String.val = Value.val

function String:new(value, range)
  if type(value) ~= "string" then
    error("String:new() expected string, got " .. typename(value))
  end
  local obj = setmetatable({}, self)
  obj._val = value
  obj._range = range
  return obj
end

function String:range(a, b) return self._range(a, b) end

function String:string() return self._val end

function String:__len() return #self:val() end

function String:ether() return self:range(), Address.ether(self:val()) end

function String:ipv4() return self:range(), Address.ipv4(self:val()) end

function String:ipv6() return self:range(), Address.ipv6(self:val()) end

function String:number()
  -- converts the number inside string to an actual number Value
  local val = self:val()
  local n = tonumber(val)
  if n then
    return Value:new(n, self:range())
  end
  return nil
end

function String:time()
  return self:number():time()
end

local parse_string0

function String:sub(str_start, str_end)
  local range = self:range()
  local rng_before = 0
  if str_start > 1 then
    _, rng_before = parse_string0(range, 0, str_start)
  end
  local _, rng_size = parse_string0(range, rng_before, str_end - str_start + 1)
  rng_size = rng_size - 1
  return String:new(self:val():sub(str_start, str_end), range(rng_before, rng_size))
end

local Object = {}
Object.__index = Object
Object.__name = "Object"
Object.__json_type = "object"
Object.__tostring = Value.__tostring
Object.__call = Value.__call

function Object:new(value, range)
  local obj = setmetatable({}, self)
  obj._val = {}
  obj._range = range
  if value and type(value) == "table" then
    for k, v in pairs(value) do
      obj[k] = v
    end
  end
  return obj
end

function Object:__pairs() return pairs(self:val()) end

function Object:__index(key)
  -- if key starts with _ then only retrieve from the object
  if key:sub(1, 1) == "_" then
    return rawget(self, key)
  end

  obj = rawget(self, "_val")
  local found = obj[key]
  if found then
    return found
  end
  for k, v in pairs(obj) do
    if k:val() == key then
      return v
    end
  end

  return rawget(self, key)
end

function Object:__newindex(key, value)
  if key:sub(1, 1) == "_" then
    return rawset(self, key, value)
  end
  rawget(self, "_val")[key] = value
end

local Array = {}
Array.__index = Array
Array.__name = "Array"
Array.__json_type = "array"
Array.__tostring = Value.__tostring
Array.__call = Value.__call

function Array:new(value, range)
  local obj = setmetatable({}, self)
  obj._val = {}
  obj._range = range
  if value and type(value) == "table" then
    for i, v in ipairs(value) do
      obj[i] = v
    end
  end
  return obj
end

function Array:__index(key)
  if type(key) == "number" then
    return rawget(self, "_val")[key]
  end
  if Array[key] then
    return Array[key]
  end
  return rawget(self, key)
end

function Array:__newindex(key, value)
  if type(key) == "number" then
    rawget(self, "_val")[key] = value
    return
  end
  rawset(self, key, value)
end

function Array:__len() return #self:val() end

function Array:__ipairs() return ipairs(self:val()) end

function Array:__pairs() return ipairs(self:val()) end

function Array:val() return self._val end

function Array:range() return self._range end

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[select(i, ...)] = true
  end
  return res
end

local space_chars  = create_set(" ", "\t", "\r", "\n")
local delim_chars  = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals     = create_set("true", "false", "null")

local literal_map  = {
  ["true"] = true,
  ["false"] = false,
  ["null"] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end

local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error(string.format("%s at line %d col %d", msg, line_count, col_count))
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
      f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error(string.format("invalid unicode codepoint '%x'", n))
end


local function parse_unicode_escape(s)
  local n1 = tonumber(s:sub(1, 4), 16)
  local n2 = tonumber(s:sub(7, 10), 16)
  -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end

function parse_string0(tvbr, i, max_len)
  local res = ""
  local str = tvbr:raw()
  local j = i + 1
  local k = j

  while j <= #str and (not max_len or #res + j - k < max_len) do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")
    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
            or str:match("^%x%x%x%x", j + 1)
            or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1
    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
      --return String:new(res, tvbr(i - 1 + 1, j - i - 1)), j + 1
    end

    j = j + 1
    if max_len and #res + j - k >= max_len then
      return res .. str:sub(k, j - 1), j
    end
  end

  decode_error(str, i, "expected closing quote for string")
end

local function parse_string(tvbr, i, max_len)
  local res, j = parse_string0(tvbr, i, max_len)
  return String:new(res, tvbr(i - 1 + 1, j - i - 2)), j
end

local function parse_number(tvbr, i)
  local str = tvbr:raw()
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return Value:new(n, tvbr(i - 1, x - i)), x
end


local function parse_literal(tvbr, i)
  local str = tvbr:raw()
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return Value:new(literal_map[word], tvbr(i - 1, x - i)), x
end


local function parse_array(tvbr, start)
  local res = {}
  local str = tvbr:raw()
  local n = 1
  local i = start
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(tvbr, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return Array:new(res, tvbr(start - 1, i - start)), i
end


local function parse_object(tvbr, start)
  local res = {}
  local str = tvbr:raw()
  local i = start
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(tvbr, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(tvbr, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return Object:new(res, tvbr(start - 1, i - start)), i
end


local char_func_map = {
  ['"'] = parse_string,
  ["0"] = parse_number,
  ["1"] = parse_number,
  ["2"] = parse_number,
  ["3"] = parse_number,
  ["4"] = parse_number,
  ["5"] = parse_number,
  ["6"] = parse_number,
  ["7"] = parse_number,
  ["8"] = parse_number,
  ["9"] = parse_number,
  ["-"] = parse_number,
  ["t"] = parse_literal,
  ["f"] = parse_literal,
  ["n"] = parse_literal,
  ["["] = parse_array,
  ["{"] = parse_object,
}


parse = function(tvbr, idx)
  local chr = tvbr(idx - 1, 1):raw()
  if chr == '' then
    decode_error(tvbr, idx, "unexpected end of input")
  end
  local f = char_func_map[chr]
  if f then
    return f(tvbr, idx)
  end
  decode_error(tvbr, idx, "unexpected character '" .. chr .. "'")
end

function jsond.decode(tvbr)
  if typename(tvbr) == "Tvb" then
    tvbr = tvbr()
  end
  if typename(tvbr) ~= "TvbRange" then
    error("expected TvbRange, got " .. typename(tvbr))
  end
  local str = tvbr:raw()
  local res, idx = parse(tvbr, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= tvbr:len() then
    decode_error(tvbr, idx, "trailing garbage")
  end
  return res
end

return jsond
