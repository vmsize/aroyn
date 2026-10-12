-- Hub-only filesystem adapter. The reusable UI core remains unchanged.
local Storage={}
local Http=game:GetService("HttpService")
local function safeName(name)
    if type(name)~="string" or #name<1 or #name>64 or not name:match("^[a-zA-Z0-9][a-zA-Z0-9_-]*$") then return nil end
    return name:lower()
end
-- Tiny independent records: no keys, active automation or profile values here.
function Storage.Record(path,validate)
    local self={Path=path,Available=type(readfile)=="function" and type(writefile)=="function"}
    function self:Read()
        if not self.Available then return nil,"SessionOnly" end
        if type(isfile)=="function" then
            local checked,exists=pcall(isfile,path)
            if not checked then return nil,"ReadFailed" end
            if not exists then return nil,"Missing" end
        end
        local ok,raw=pcall(readfile,path)
        if not ok then return nil,"ReadFailed" end
        local parsed,data=pcall(Http.JSONDecode,Http,raw)
        if not parsed or type(data)~="table" or not validate(data) then return nil,"InvalidRecord" end
        return data
    end
    function self:Write(data)
        if not self.Available then return false,"SessionOnly" end
        if not validate(data) then return false,"InvalidRecord" end
        local ok=pcall(function()
            local folder=""
            for part in path:match("^(.*)/"):gmatch("[^/]+") do
                folder=folder=="" and part or folder.."/"..part
                if type(makefolder)=="function" and (type(isfolder)~="function" or not isfolder(folder)) then makefolder(folder) end
            end
            local raw=Http:JSONEncode(data)
            writefile(path,raw)
            assert(readfile(path)==raw,"Readback mismatch")
        end)
        if ok then return true end
        return false,"WriteFailed"
    end
    return self
end
function Storage.Preferences(window,info,warn)
    local cfg=window.Config
    local record=Storage.Record(info.StorageRoot.."/preferences-"..info.Namespace..".json",function(d)
        return d.SchemaVersion==1 and safeName(d.Profile)~=nil and type(d.AutoSave)=="boolean"
    end)
    local data,readError=record:Read()
    local self={Profile=data and data.Profile or "main",AutoSave=not data or data.AutoSave,Record=record}
    if readError and readError~="Missing" then warn("Preference metadata unavailable ("..readError..").") end
    function self:Remember()
        local ok,why=record:Write({SchemaVersion=1,Profile=self.Profile,AutoSave=self.AutoSave})
        if not ok then warn("Preference selection could not be saved ("..why..").") end
        return ok
    end
    function self:Select(name)
        name=safeName(name);if not name then return end
        self.Profile=name;cfg.AutoSaveName=name
        if data==nil or data.Profile~=name then self:Remember();data={Profile=name} end
    end
    function self:SetAutoSave(enabled)
        if cfg.SaveJob then self:Flush() end
        self.AutoSave=enabled;window:SetConfigAutoSave(enabled,self.Profile,.75);self:Remember()
    end
    function self:Flush()
        if cfg.Alive and cfg.SaveJob and self.AutoSave then
            cfg:_CancelSave();return cfg:Save(self.Profile)
        end
        return true
    end
    local save=cfg.Save
    cfg.Save=function(manager,name)
        local ok,result=save(manager,name)
        if not ok then warn("Preferences could not be saved ("..tostring(result.Code)..").")
        elseif safeName(name) then self:Select(name) end
        return ok,result
    end
    return self
end
function Storage.FileSystem(root,namespace)
    local fs={};local logical="AroynUILab/configs/"..namespace.."/";local physical=root.."/profiles/"..namespace.."/"
    local function map(path)
        if path=="AroynUILab" then return root end
        if path=="AroynUILab/configs" then return root.."/profiles" end
        if path:sub(1,#logical)==logical then return physical..path:sub(#logical+1) end
        if path==logical:sub(1,-2) then return physical:sub(1,-2) end
        return path
    end
    local functions={isfolder=isfolder,makefolder=makefolder,isfile=isfile,readfile=readfile,writefile=writefile,delfile=delfile,listfiles=listfiles}
    for key,fn in pairs(functions) do
        if type(fn)=="function" then
            fs[key]=function(path,...)
                local result=fn(map(path),...)
                if key=="listfiles" and type(result)=="table" then
                    local mapped={}
                    for _,p in pairs(result) do
                        if type(p)=="string" then
                            p=p:gsub("\\","/")
                            local start=p:find(physical,1,true)
                            if start and (start==1 or p:sub(start-1,start-1)=="/") then p=logical..p:sub(start+#physical) end
                            table.insert(mapped,p)
                        end
                    end
                    return mapped
                end
                return result
            end
        end
    end
    return fs
end
function Storage.Bind(window,info)
    local cfg=window.Config;local fs=cfg.FileSystem
    local write,read=fs.writefile,fs.readfile
    local backupRoot=info.StorageRoot.."/profile-backups/"..info.Namespace.."/"
    local self={Window=window,Config=cfg,BackupRoot=backupRoot}
    if cfg.Mode~="File" then
        function self:Restore() return false,{Code="SessionOnly",Message="Recovery copies require file storage"} end
        return self
    end
    local function decoded(raw)
        if type(raw)~="string" or #raw>262144 then return nil end
        local ok,data=pcall(Http.JSONDecode,Http,raw);return ok and type(data)=="table" and data or nil
    end
    local function valid(raw)
        local data=decoded(raw)
        if not data or data.SchemaVersion~=1 or data.Namespace~=info.Namespace or type(data.Values)~="table" then return false end
        local count=0
        for key,record in pairs(data.Values) do
            count+=1
            if count>512 or type(key)~="string" or type(record)~="table" then return false end
            local t,v=record.Type,record.Value
            if t=="Input" then if type(v)~="string" or #v>16384 then return false end
            elseif t=="Toggle" then if type(v)~="boolean" then return false end
            elseif t=="Slider" then if type(v)~="number" or v~=v or math.abs(v)==math.huge then return false end
            elseif t=="Dropdown" then
                if record.Multi then if type(v)~="table" then return false end;for _,x in pairs(v) do if type(x)~="string" then return false end end
                elseif type(v)~="string" and v~=false then return false end
            elseif t=="Keybind" then if type(v)~="table" or type(v.Key)~="string" or not table.find({"Toggle","Hold","Always"},v.Mode) then return false end
            else return false end
        end
        return true
    end
    local function get(path) local ok,raw=pcall(read,path);return ok and raw or nil end
    local function ensureBackup()
        if type(fs.makefolder)=="function" then
            for _,p in ipairs({info.StorageRoot,info.StorageRoot.."/profile-backups",backupRoot:sub(1,-2)}) do
                if type(fs.isfolder)~="function" or not fs.isfolder(p) then fs.makefolder(p) end
            end
        end
    end
    fs.writefile=function(path,raw)
        local name=path:sub(1,#cfg.Path)==cfg.Path and safeName(path:sub(#cfg.Path+1):match("^(.-)%.json$"))
        if not name then return write(path,raw) end -- __index and unrelated operations are core-owned.
        assert(valid(raw),"Profile payload failed validation")
        local old=get(path);local oldData=decoded(old)
        assert(old==nil or valid(old),"Existing profile is invalid; restore a backup or explicitly delete it")
        assert(not oldData or oldData.SchemaVersion==1,"Unsupported profile schema; existing file kept")
        assert(not oldData or oldData.Namespace==info.Namespace,"Profile namespace mismatch; existing file kept")
        local backup=backupRoot..name..".json"
        if valid(old) then
            ensureBackup();write(backup,old)
            assert(get(backup)==old,"Recovery copy could not be verified; profile kept")
        else old=get(backup);if not valid(old) then old=nil end end
        local ok,err=pcall(write,path,raw)
        if ok and get(path)==raw then return end
        if old then
            local restored=pcall(write,path,old)
            if restored and get(path)==old then error("Profile write failed; previous profile restored",0) end
            error("Profile write failed; recovery copy retained; restore required",0)
        end
        error("Profile write failed; no prior recovery copy: "..tostring(err or "readback mismatch"),0)
    end
    function self:Restore(name)
        return cfg:_Run(function()
            name=safeName(name);if not name then return cfg:_Result(false,"InvalidName","Invalid profile name") end
            cfg:_CancelSave()
            local raw=get(backupRoot..name..".json")
            if not valid(raw) then return cfg:_Result(false,"BackupUnavailable","A valid recovery copy is unavailable") end
            local names,code,detail=cfg:_Names()
            if not names then return cfg:_Result(false,code,detail) end
            local ready,err=cfg:_EnsureFolder();if not ready then return cfg:_Result(false,"FolderFailed",err) end
            local ok,why=pcall(write,cfg.Path..name..".json",raw)
            if not ok or get(cfg.Path..name..".json")~=raw then return cfg:_Result(false,"RestoreFailed",tostring(why or "Readback mismatch")) end
            if not table.find(names,name) then table.insert(names,name);table.sort(names) end
            local indexed,message=cfg:_WriteIndex(names)
            if not indexed then return cfg:_Result(false,"IndexWriteFailed",message,{FileSaved=true}) end
            return cfg:_Result(true,"Restored","Previous saved profile restored")
        end)
    end
    return self
end
return Storage
