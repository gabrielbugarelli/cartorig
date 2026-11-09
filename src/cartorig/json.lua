-- CartoRig self-contained JSON codec; untrusted input is data, never Lua source.
local M={}
local function fail(s,i)error('CartoRig JSON: '..s..' at byte '..tostring(i or '?'),2)end
local function array(t)
  local n=0;local total=0
  for k in pairs(t) do
    if type(k)~='number' or k<1 or k%1~=0 then return nil end
    if k>n then n=k end
    total=total+1
  end
  if total~=n then return nil end
  return n
end
local function quote(s)
  local specials={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)return specials[c] or string.format('\\u%04X',c:byte()) end)..'"'
end
function M.encode(value)
  local seen={}
  local function encode(v,depth)
    if depth>100 then fail('nesting too deep') end
    local typ=type(v)
    if typ=='nil' then return 'null' end
    if typ=='boolean' then return tostring(v) end
    if typ=='string' then return quote(v) end
    if typ=='number' then
      if v~=v or v==math.huge or v==-math.huge then fail('nonfinite number') end
      return string.format('%.17g',v)
    end
    if typ~='table' or seen[v] then fail('unsupported value or cyclic table') end
    seen[v]=true
    local result={}
    local n=array(v)
    if n then
      for i=1,n do result[#result+1]=encode(v[i],depth+1) end
      seen[v]=nil;return '['..table.concat(result,',')..']'
    end
    for k,child in pairs(v) do
      if type(k)~='string' then fail('object key must be string') end
      result[#result+1]={key=k,encoded=quote(k)..':'..encode(child,depth+1)}
    end
    table.sort(result,function(a,b)return a.key<b.key end)
    local list={};for i,item in ipairs(result) do list[i]=item.encoded end
    seen[v]=nil;return '{'..table.concat(list,',')..'}'
  end
  return encode(value,0)
end
local function utf8char(n)
  if n<0x80 then return string.char(n) end
  if n<0x800 then return string.char(0xc0+math.floor(n/64),0x80+n%64) end
  if n<0x10000 then return string.char(0xe0+math.floor(n/4096),0x80+math.floor(n/64)%64,0x80+n%64) end
  return string.char(0xf0+math.floor(n/262144),0x80+math.floor(n/4096)%64,0x80+math.floor(n/64)%64,0x80+n%64)
end
function M.decode(input,maxlen)
  if type(input)~='string' then fail('expected text') end
  maxlen=maxlen or 20000000
  if #input>maxlen then fail('payload too large') end
  local i,n=1,#input
  local function white()
    while true do local c=input:byte(i);if c==32 or c==9 or c==10 or c==13 then i=i+1 else break end end
  end
  local function stringval()
    local parts={};i=i+1
    while i<=n do
      local c=input:byte(i)
      if c==34 then i=i+1;return table.concat(parts) end
      if c<32 then fail('control in string',i) end
      if c==92 then
        local e=input:sub(i+1,i+1)
        local back={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if back[e] then parts[#parts+1]=back[e];i=i+2
        elseif e=='u' then
          local hex=input:sub(i+2,i+5)
          if #hex~=4 or not hex:match('^%x%x%x%x$') then fail('bad unicode escape',i) end
          local cp=tonumber(hex,16);i=i+6
          if cp>=0xD800 and cp<=0xDBFF then
            if input:sub(i,i+1)~='\\u' then fail('missing low surrogate',i) end
            local low=input:sub(i+2,i+5)
            if not low:match('^%x%x%x%x$') then fail('invalid low surrogate',i) end
            local lo=tonumber(low,16)
            if lo<0xDC00 or lo>0xDFFF then fail('invalid low surrogate',i) end
            cp=0x10000+(cp-0xD800)*1024+(lo-0xDC00);i=i+6
          elseif cp>=0xDC00 and cp<=0xDFFF then fail('unexpected low surrogate',i) end
          parts[#parts+1]=utf8char(cp)
        else fail('bad escape',i) end
      else
        -- Scan one UTF-8 byte at a time; source encoding validated by upstream distribution.
        parts[#parts+1]=string.char(c);i=i+1
      end
    end
    fail('unterminated string',i)
  end
  local value
  value=function(depth)
    if depth>100 then fail('nesting too deep',i) end
    white()
    local c=input:sub(i,i)
    if c=='"' then return stringval() end
    if c=='{' then
      i=i+1;white();local obj={}
      if input:sub(i,i)=='}' then i=i+1;return obj end
      while true do
        white();if input:sub(i,i)~='"' then fail('object key expected',i) end
        local k=stringval();white()
        if input:sub(i,i)~=':' then fail('colon expected',i) end
        i=i+1
        if obj[k]~=nil then fail('duplicate object key',i) end
        obj[k]=value(depth+1);white()
        local d=input:sub(i,i);i=i+1
        if d=='}' then break elseif d~=',' then fail('object delimiter expected',i) end
      end
      return obj
    elseif c=='[' then
      i=i+1;white();local a={}
      if input:sub(i,i)==']' then i=i+1;return a end
      while true do
        a[#a+1]=value(depth+1);white()
        local d=input:sub(i,i);i=i+1
        if d==']' then break elseif d~=',' then fail('array delimiter expected',i) end
      end
      return a
    elseif input:sub(i,i+3)=='true' then i=i+4;return true
    elseif input:sub(i,i+4)=='false' then i=i+5;return false
    elseif input:sub(i,i+3)=='null' then i=i+4;return M.null
    else
      local tail=input:sub(i)
      local num=tail:match('^-?%d+%.?%d*[eE]?[+%-]?%d*')
      if not num or num=='' or not num:match('^-?(0|[1-9]%d*)') then
        -- Lua patterns do not support alternation; check via tonumber and grammar below.
        if not num or num=='' then fail('invalid value',i) end
      end
      if not num:match('^-?%d+%.?%d*[eE]?[+%-]?%d*$') or
         num:match('^%-?0%d') or num:match('%.$') or num:match('[eE][+%-]?$') then fail('bad number',i) end
      local number=tonumber(num)
      if not number or number==math.huge or number==-math.huge then fail('invalid numeric range',i) end
      i=i+#num;return number
    end
  end
  local result=value(0);white()
  if i<=n then fail('trailing content',i) end
  return result
end
M.null=setmetatable({},{__tostring=function()return 'null' end})
return M
