--
-- json_de.lua
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

local json_de = { _version = "0.0.1" }

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

Value = {}
Value.__index = Value

function Value:new(value, range)
  local obj = setmetatable({}, self)
  obj._range = range
  obj._val = value
  return obj
end

function Value:__tostring()
  return tostring(self._val)
end

function Value:range()
  return self._range
end

function Value:val()
  return self._val
end

local String = {}
String.__index = String

function String:new(value, range)
  local obj = setmetatable({}, self)
  obj._range = range
  obj._val = value
  return obj
end

function String:__tostring()
  return self._val
end

function String:range(a, b)
  return self._range(a, b)
end

function String:val()
  return self._val
end

local parse_string0

function String:sub(a, b)
  local r = self:range()
  local _, ra = parse_string0(r, 0, a)
  local _, rb = parse_string0(r, ra, b - a)
  return Value:new(self:range(ra, rb), self:val():sub(a, b))
end

local xxx = 0

function String:__index(key)
  if String[key] then
    return String[key]
  end

  xxx = xxx + 1
  if xxx > 4 then
    print(debug.traceback())
    os.exit(1)
  end
  return String:new(self:range(key - 1, 1), self:val():sub(key, key))
end

local Object = {}
Object.__index = Object

function Object:new(value, range)
  local obj = setmetatable({}, self)
  rawset(obj, "_val", {})
  rawset(obj, "_range", range)
  if value and type(value) == "table" then
    for k, v in pairs(value) do
      obj[k] = v
    end
  end
  return obj
end

function Object:range() return rawget(self, "_range") end

function Object:val() return rawget(self, "_val") end

function Object:__pairs() return pairs(self:val()) end

function Object:__index(key)
  local class_field = rawget(Object, key)
  if class_field then
    return class_field
  end
  local obj = rawget(self, "_val")
  local found = obj[key]
  if found then
    return found
  end
  for k, v in pairs(obj) do
    if k:val() == key then
      return v
    end
  end
  return nil
end

function Object:__newindex(key, value)
  rawget(self, "_val")[key] = value
end

local Array = {}
Array.__index = Array

function Array:new(value, range)
  local obj = setmetatable({}, self)
  obj._range = range
  obj._val = value or {}
  return obj
end

function Array:range()
  return rawget(self, "_range")
end

function Array:val()
  return rawget(self, "_val")
end

function Array:__index(key)
  if Array[key] then
    return Array[key]
  end
  return self:val()[key]
end

function Array:__tostring() return tostring(self:val()) end

function Array:__len() return #self:val() end

function Array:__ipairs() return ipairs(self:val()) end

function Array:__pairs() return ipairs(self:val()) end

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
  print(debug.traceback())
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

  while j <= #str and (not max_len or #res < max_len) do
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
  end

  decode_error(str, i, "expected closing quote for string")
end

local function parse_string(tvbr, i, max_len)
  local res, j = parse_string0(tvbr, i, max_len)
  return String:new(res, tvbr(i - 1 + 1, j - i - 2)), j
end

local function parse_number(tvbr, i)
  print("parse_number(" .. tostring(tvbr) .. ", " .. tostring(i) .. ")")
  local str = tvbr:raw()
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  print("parse_number: " .. s .. " = " .. tostring(n))
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
  print("parse(" .. tostring(tvbr) .. ", " .. tostring(idx) .. ")")
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

function json_de.decode(tvbr)
  if typename(tvbr) == "Tvb" then
    tvbr = tvbr()
  end
  if typename(tvbr) ~= "TvbRange" then
    error("expected TvbRange, got " .. typename(tvbr))
  end
  local res, idx = parse(tvbr, next_char(tvbr, 1, space_chars, true))
  idx = next_char(tvbr, idx, space_chars, true)
  if idx <= #tvbr then
    decode_error(tvbr, idx, "trailing garbage")
  end
  return res
end

return json_de
