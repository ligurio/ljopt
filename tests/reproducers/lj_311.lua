module('row', package.seeall)

local ffi = require("ffi")

  ffi.cdef[[
      typedef int64_t NativeInt;
  ]]

ffi.cdef[[
      #pragma pack(push, 1)
      typedef struct
      {
	 NativeInt highindex;
	 NativeInt arr[?];
      }
      TIntArrayNative;

      typedef struct
      {
	 TIntArrayNative *ptr;
      }
      PIntArrayNative;
      #pragma pack(pop)
]]


local __ArrayLenFunc =
      function(x)
	local l = -1
	if x.ptr ~= nil then
	  l = tonumber(x.ptr.highindex)
	end
	return l
      end

ffi.cdef[[
    void *calloc(size_t num, size_t size);
    void free(void *ptr);
]]
local TIntArrayNative_ffi = ffi.typeof("PIntArrayNative")

__TIntArrayNative_ctor = nil

local
TIntArrayNative_methods = {
   xMeta = function()
     return TIntArrayNative
   end,
}

local TIntArrayNative_mt = {
   __len = __ArrayLenFunc,

   __call =
      function (x)
	 return TIntArrayNative_methods
      end,

   __gc =
      function(x)
	 local f = function(x)
	   ffi.C.free(x.ptr)
	   x.ptr = nil
	 end
	 f(x)
      end,

   __index =
     function(x, i)
       return x.ptr.arr[i]
     end,

   __newindex =
     function(x, i, v)
       x.ptr.arr[i] = v
     end,
}

local __TIntArrayNative_ctor_mt = ffi.metatype("PIntArrayNative", TIntArrayNative_mt)
function __TIntArrayNative_ctor(n)
  local a = __TIntArrayNative_ctor_mt( ffi.C.calloc(n+1,8) )
  a.ptr.highindex = n-1
  return a
end

TIntArrayNative =
  {
  }

function dump(a)
  for i=0,#a do
    print(a[i]," ")
  end
end

local
  function __TIntArrayNative_new(n)
    if type(n) == 'number' then
      return __TIntArrayNative_ctor( n )
    end

    if type(n) == 'table' then
      local len = #n

      local a = __TIntArrayNative_new( len )
      local k = 0
      for _,v in ipairs(n) do
        a[k] = v
        k = k + 1
      end
      return a
    end

    assert 'Unsupported argument combination'
  end

function TimeFunc(timer, f, ...)

  local res = { f(...) }

  return table.unpack(res)
end

MemAlloc =
 {
   Enabled = false,
 }

function MemAlloc.TimeFunc(f, ...)
  if MemAlloc.Enabled then
    --return
  else
    return f(...)
  end
end

function TIntArrayNative.new(n)
  return MemAlloc.TimeFunc(__TIntArrayNative_new, n)
end

--=======================================================================
function ff(a)
  local r=TIntArrayNative.new(1+#a)

  for i=1,#a do
    if a[i] > a[i-1] then
      if r[i-1] > 0 then
        r[i] = r[i-1] + 1
      else
        r[i] = 1
      end
    end

    if a[i] < a[i-1] then
      if r[i-1] < 0 then
        r[i] = r[i-1] - 1
      else
        r[i] = -1
      end
    end
  end

  return r
end

function cEql(a1, a2)
  if #a1 ~= #a2 then
    return false
  end
  for i=0,#a1 do
    if a1[i] ~= a2[i] then
      return false
    end
  end
  return true
end

--r=TIntArrayNative.new{ 0,1,2,-1,-2,-3 }
--dump(r)
--os.exit(0)

for i=0,100 do
  jit.flush()

  r=TIntArrayNative.new{ 0,1,2,-1,-2,-3 }
  res=ff( TIntArrayNative.new{ 1,2,3,2,1,0 } )
  assert( cEql(r, res), 'ff1 failed' )

  r=TIntArrayNative.new{ 0,0,0 }
  res=ff( TIntArrayNative.new{ 0, 0, 0 } )
  assert( cEql(r, res), 'ff2 failed' )

  r=TIntArrayNative.new{ 0,1,-1 }
  res=ff( TIntArrayNative.new{ 0, 1, 0 } )
  assert( cEql(r, res), 'ff3 failed' )

  r=TIntArrayNative.new{ 0,-1,-2,-3, 1,2,3 }
  res=ff( TIntArrayNative.new{ 0,-1,-2,-4,0,1,2 } )
  assert( cEql(r, res), 'ff4 failed' )
end
