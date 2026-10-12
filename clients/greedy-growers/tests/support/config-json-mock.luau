-- Test-only JSON boundary. Unlike the older mock's opaque tokens, these are real JSON bytes.
local JSON={}
local function quoted(s)
    return '"'..s:gsub('[%z\1-\31\\"]',function(c)
        return ({['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'})[c] or string.format('\\u%04x',string.byte(c))
    end)..'"'
end
function JSON.encode(value)
    local seen={}
    local function encode(v)
        local kind=type(v)
        if kind=='boolean' then return v and 'true' or 'false' end
        if kind=='string' then return quoted(v) end
        if kind=='number' then assert(v==v and math.abs(v)<math.huge);return string.format('%.17g',v) end
        assert(kind=='table' and not seen[v],'Not JSON-safe');seen[v]=true
        local array,count=true,0
        for k in pairs(v) do count+=1;if type(k)~='number' or k%1~=0 or k<1 then array=false end end
        array=array and count==#v and count>0
        local parts={}
        if array then for _,item in ipairs(v) do table.insert(parts,encode(item)) end
        else
            local keys={};for k in pairs(v) do assert(type(k)=='string');table.insert(keys,k) end;table.sort(keys)
            for _,k in ipairs(keys) do table.insert(parts,quoted(k)..':'..encode(v[k])) end
        end
        seen[v]=nil;return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
    end
    return encode(value)
end
function JSON.decode(s)
    assert(type(s)=='string');local p=1
    local function skip() local _,e=s:find('^%s*',p);p=(e or p-1)+1 end
    local parse
    local function str()
        assert(s:sub(p,p)=='"');p+=1;local parts={}
        while p<=#s do
            local c=s:sub(p,p);p+=1
            if c=='"' then return table.concat(parts) end
            if c=='\\' then
                local e=s:sub(p,p);p+=1
                if e=='u' then
                    local raw=s:sub(p,p+3);assert(raw:match('^%x%x%x%x$'));p+=4
                    table.insert(parts,utf8.char(tonumber(raw,16)))
                else
                    local decoded=({['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'})[e]
                    assert(decoded);table.insert(parts,decoded)
                end
            else assert(string.byte(c)>=32);table.insert(parts,c) end
        end
        error('Unterminated JSON string')
    end
    parse=function()
        skip();local c=s:sub(p,p)
        if c=='"' then return str() end
        if c=='{' or c=='[' then
            local close=c=='{' and '}' or ']';local object=c=='{';local out={};p+=1;skip()
            if s:sub(p,p)==close then p+=1;return out end
            while true do
                skip();local k
                if object then k=str();skip();assert(s:sub(p,p)==':');p+=1 else k=#out+1 end
                out[k]=parse();skip();local nextChar=s:sub(p,p);p+=1
                if nextChar==close then return out end
                assert(nextChar==',')
            end
        end
        for literal,value in pairs({['true']=true,['false']=false}) do
            if s:sub(p,p+#literal-1)==literal then p+=#literal;return value end
        end
        if s:sub(p,p+3)=='null' then p+=4;return nil end
        local raw=s:match('^%-?%d+%.?%d*[eE]?[+-]?%d*',p);local n=raw and tonumber(raw)
        assert(n and n==n and math.abs(n)<math.huge,'Invalid JSON value');p+=#raw;return n
    end
    local value=parse();skip();assert(p>#s,'Trailing JSON');return value
end
return JSON
