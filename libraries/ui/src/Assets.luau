-- Generic local embedded-image adapter. No GUI, global registry or network.
return function(Aroyn, payload)
    local register=type(getcustomasset)=="function" and getcustomasset or getsynasset
    local report={Status="Unavailable",Images={},Errors={}}
    local function decode(s)
        local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local values={};for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
        local chunks={}
        for i=1,#s,4 do
            local a,b=values[s:sub(i,i)],values[s:sub(i+1,i+1)]
            local c,d=values[s:sub(i+2,i+2)],values[s:sub(i+3,i+3)]
            assert(a and b,"Aroyn distribution: corrupt embedded base64")
            local n=a*262144+b*4096+(c or 0)*64+(d or 0)
            chunks[#chunks+1]=string.char(math.floor(n/65536)%256)
            if c then chunks[#chunks+1]=string.char(math.floor(n/256)%256) end
            if d then chunks[#chunks+1]=string.char(n%256) end
        end
        return table.concat(chunks)
    end
    if type(writefile)~="function" or type(register)~="function" then
        report.Errors[1]="Embedded images require writefile and getcustomasset/getsynasset. Icon slots remain empty; supply ready Aroyn.IconAtlas and Logo URIs before construction."
    else
        local directory="AroynUI/assets"
        local ok,reason=pcall(function()
            if type(makefolder)=="function" then
                for _,folder in ipairs({"AroynUI",directory}) do
                    local exists=false
                    if type(isfolder)=="function" then local success,result=pcall(isfolder,folder);exists=success and result==true end
                    if not exists then
                        local made,problem=pcall(makefolder,folder)
                        if not made and not (type(isfolder)=="function" and isfolder(folder)) then error(problem) end
                    end
                end
            end
        end)
        if not ok then report.Errors[#report.Errors+1]="Asset directory unavailable: "..tostring(reason) end
        for _,image in ipairs(payload) do
            local success,uri=pcall(function()
                assert(ok,reason)
                local bytes=decode(image.Base64)
                assert(bytes:sub(1,8)=="\137PNG\13\10\26\10","Invalid embedded PNG")
                local path=directory.."/"..image.SHA256..".png"
                local cached=false
                if type(readfile)=="function" then local read,value=pcall(readfile,path);cached=read and value==bytes end
                if not cached then writefile(path,bytes) end
                local value=register(path)
                assert(type(value)=="string" and value~="","Custom asset registration returned no URI")
                return value
            end)
            if success then Aroyn[image.Field]=uri;report.Images[image.Field]=uri
            else report.Errors[#report.Errors+1]=image.Field..": "..tostring(uri) end
        end
        if #report.Errors==0 then report.Status="Ready"
        elseif next(report.Images) then report.Status="Partial" end
    end
    if report.Status~="Ready" then warn("Aroyn UI distribution: "..table.concat(report.Errors," | ")) end
    return report
end
