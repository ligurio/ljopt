local seed = tonumber(arg[1]) or 1
math.randomseed(seed)

local M = 1000003
local function pick(t) return t[math.random(#t)] end
local function rnd(n) return math.random(n) end

local VARS = { "a", "b", "c", "i", "j", "n" }
local SMALL = { "0", "1", "2", "3", "7", "13", "31", "127", "1000",
                "65535", "-1", "-7", "-1000" }
local TABS = { "t1", "t2", "t3" }
local KEYS = { "1", "2", "3", "4", "5",
               "((i % 8) + 1)",
               "((j % 4) + 1)", "'ka'", "'kb'",
               "'kc'", "((n % 6) + 1)" }

local function ex(d)
  d = d or 0
  if d > 3 then return pick(VARS) end
  local k = rnd(11)
  if k <= 3 then return pick(VARS)
  elseif k == 4 then return pick(SMALL)
  elseif k == 5 then return ("((%s + %s) %% %d)"):format(ex(d+1), ex(d+1), M)
  elseif k == 6 then return ("((%s - %s) %% %d)"):format(ex(d+1), ex(d+1), M)
  elseif k == 7 then
    return ("((%s * 31 + %s) %% %d)"):format(ex(d+1), ex(d+1), M)
  elseif k == 8 then
    return ("(g(%s) [ %s ] or 0)"):format(pick(TABS), pick(KEYS))
  elseif k == 9 then return ("#%s"):format(pick(TABS))
  elseif k == 10 then
    return ("((%s < %s) and %s or %s)")
      :format(ex(d+1), ex(d+1), ex(d+1), ex(d+1))
  else return ("bit.band(%s, 65535)"):format(ex(d+1)) end
end

local stmts, nloc = {}, 0
local function em(s) stmts[#stmts+1] = s end

local function stmt(ind, d)
  local pad = ("  "):rep(ind)
  local k = rnd(d < 2 and 14 or 9)
  if k == 1 then
    em(("%s%s[%s] = %s"):format(pad, pick(TABS), pick(KEYS), ex()))
  elseif k == 2 then em(("%sa = %s"):format(pad, ex()))
  elseif k == 3 then em(("%sb = %s"):format(pad, ex()))
  elseif k == 4 then
    local t, o, key = pick(TABS), pick(TABS), pick(KEYS)
    em(("%slocal u = ((%s) < (%s)) and %s or %s")
      :format(pad, ex(), ex(), t, o))
    em(("%s%s[%s] = %s"):format(pad, t, key, ex()))
    em(("%su[%s] = %s"):format(pad, key, ex()))
    em(("%sn = (n + (%s[%s] or 0) + (u[%s] or 0)) %% %d")
      :format(pad, t, key, key, M))
  elseif k == 5 then em(("%sn = (n + %s) %% %d"):format(pad, ex(), M))
  elseif k == 6 then
    nloc = nloc + 1
    local v = "s" .. nloc
    em(("%slocal %s = { %s, %s }"):format(pad, v, ex(), ex()))
    if rnd(2) == 1 then
      em(("%st3[%s] = (%s[1] + %s[2]) %% %d")
        :format(pad, pick(KEYS), v, v, M))
    else
      em(("%sn = (n + %s[1] - %s[2]) %% %d"):format(pad, v, v, M))
    end
  elseif k == 7 then
    em(("%sif (%s) < (%s) then"):format(pad, ex(), ex())); stmt(ind+1, d+1)
    em(("%selse"):format(pad)); stmt(ind+1, d+1); em(("%send"):format(pad))
  elseif k == 8 then
    em(("%sfor j = 1, %d do"):format(pad, rnd(5))); stmt(ind+1, d+1)
    stmt(ind+1, d+1); em(("%send"):format(pad))
  elseif k == 9 then
    em(("%sn = (n + ((%s) < (%s) and 1 or 2)) %% %d")
      :format(pad, ex(), ex(), M))
  elseif k == 10 then
    em(("%stable.insert(t2, %s)"):format(pad, ex()))
    em(("%sif #t2 > 10 then table.remove(t2, 1) end"):format(pad))
  elseif k == 11 then
    em(("%sdo local f = function() return (a + b) %% %d end " ..
        "n = (n + f()) %% %d end"):format(pad, M, M))
  elseif k == 12 then
    em(("%sif i == %d then n = (n + 12345) %% %d end")
      :format(pad, 50 + rnd(200), M))
  elseif k == 13 then
    em(("%sc = (c * 31 + %s) %% %d"):format(pad, ex(), M))
  else
    em(("%sn = (n + #t1 + #t2 + #t3) %% %d"):format(pad, M))
  end
end

local o = {}
local function w(s) o[#o+1] = s end
w("local function g(t) return t end")
w("local t1, t2, t3 = {}, {}, {}")
w("for k = 1, 8 do t1[k] = k t2[k] = k * 2 t3[k] = k * 3 end")
w("t1.ka, t1.kb, t1.kc = 1, 2, 3")
w("t2.ka, t2.kb, t2.kc = 4, 5, 6")
w("t3.ka, t3.kb, t3.kc = 7, 8, 9")
w("local a, b, c, n = 1, 2, 3, 0")
w("local j = 0")
w("local log = {}")
w("for i = 1, 400 do")
for _ = 1, 8 + rnd(8) do stmt(1, 0) end
w("  n = (n + a + b + c) % 1000003")
w("  if i % 97 == 0 then log[#log+1] = n end")
w("end")
w("local acc = n")
w("for k = 1, 10 do")
w("  acc = (acc * 31 + (tonumber(t1[k]) or 0) + (tonumber(t2[k]) or 0)")
w("        + (tonumber(t3[k]) or 0)) % 1000003")
w("end")
w("for _, kk in ipairs({'ka','kb','kc'}) do")
w("  acc = (acc * 31 + (tonumber(t1[kk]) or 0) + (tonumber(t2[kk]) or 0)")
w("        + (tonumber(t3[kk]) or 0)) % 1000003")
w("end")
w("for _, v in ipairs(log) do acc = (acc * 31 + v) % 1000003 end")
w("print(acc, #t1, #t2, #t3, a, b, c, n)")

local body = table.concat(stmts, "\n")
local text = table.concat(o, "\n")
text = text:gsub("for i = 1, 400 do", function()
  return "for i = 1, 400 do\n" .. body end, 1)
io.write(text, "\n")
