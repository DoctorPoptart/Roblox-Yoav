local xml = (function()
    -- from https://github.com/jonathanpoelen/lua-xmlparser

    -- http://lua-users.org/wiki/StringTrim

    local slashchar = string.byte('/', 1)
    local E = string.byte('E', 1)

    local function defaultEntityTable()
        return { quot='"', apos='\'', lt='<', gt='>', amp='&', tab='\t', nbsp=' ', }
    end

    local function replaceEntities(s, entities)
        return s:gsub('&([^;]+);', entities)
    end

    local function createEntityTable(docEntities, resultEntities)
    local entities = resultEntities or defaultEntityTable()
    for _,e in pairs(docEntities) do
        e.value = replaceEntities(e.value, entities)
        entities[e.name] = e.value
    end
        return entities
    end

    local function parse(s, evalEntities)

    s = s:gsub('<!%-%-(.-)%-%->', '')

    local entities, tentities = {}
    
    if evalEntities then
        local pos = s:find('<[_%w]')
        if pos then
            s:sub(1, pos):gsub('<!ENTITY%s+([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
                entities[#entities+1] = {name=name, value=entity}
            end)
            tentities = createEntityTable(entities)
            s = replaceEntities(s:sub(pos), tentities)
        end
    end

    local t, l = {}, {}

    local special_characters = {
        ["&apos;"] = "'",
        ["&quot;"] = '"',
        ["&amp;"] = "&",
        ["&lt;"] = "<",
        ["&gt;"] = ">"
    }

    local addtext = function(txt)
        txt = txt:match'^%s*(.*%S)' or ''

        for key, value in pairs(special_characters) do
            txt = txt:gsub(key, value)    
        end

        if #txt ~= 0 then
        t[#t+1] = {text=txt}
        end    
    end
    
    s:gsub('<([?!/]?)([-:_%w]+)%s*(/?>?)([^<]*)', function(type, name, closed, txt)
        -- open
        if #type == 0 then
        local attrs, orderedattrs = {}, {}
        if #closed == 0 then
            local len = 0
            for all,aname,_,value,starttxt in string.gmatch(txt, "(.-([-_%w]+)%s*=%s*(.)(.-)%3%s*(/?>?))") do
            len = len + #all
            attrs[aname] = value
            orderedattrs[#orderedattrs+1] = {name=aname, value=value}
            if #starttxt ~= 0 then
                txt = txt:sub(len+1)
                closed = starttxt
                break
            end
            end
        end
        t[#t+1] = {tag=name, attrs=attrs, children={}, orderedattrs=orderedattrs}

        if closed:byte(1) ~= slashchar then
            l[#l+1] = t
            t = t[#t].children
        end

        addtext(txt)
        -- close
        elseif '/' == type then
        t = l[#l]
        l[#l] = nil

        addtext(txt)
        elseif '!' == type then
            if E == name:byte(1) then
                txt:gsub('([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
                entities[#entities+1] = {name=name, value=entity}
                end, 1)
            end
        end
    end)

    return {children=t, entities=entities, tentities=tentities}
    end

    return {
        parse = parse,
        defaultEntityTable = defaultEntityTable,
        replaceEntities = replaceEntities,
        createEntityTable = createEntityTable,
    }
end)()

;(function()
    if not getgenv then return end

    local global_environment = getgenv()
    local _require = global_environment.require

    if not _require then return end
    if global_environment.yoav_loaded then return end
    global_environment.yoav_loaded = {}
    global_environment.yoav_instances = {}

    local function require(module)
        if typeof(module) == "userdata" and getmetatable(module).__type == "ModuleScript" then
            local contents = yoav_loaded[module]
            if not contents then
                contents = {module:load()}
                yoav_loaded[module] = contents
            end

            return unpack(contents)
        else
            return _require(module)
        end
    end

    global_environment.require = require
end)()

local function find_first_tag(xml_node, tag, layer)
    layer = layer or 0
    
    local node_tag = xml_node.tag
    local node_children = xml_node.children
    if not node_children or layer >= 10 then return end

    if node_tag == tag then return xml_node end

    for index, node in ipairs(node_children) do
        local result = find_first_tag(node, tag, layer+1)
        if result then return result end
    end
end

local types = {}

function types.string(params)       
    return (#params > 0 and params[1].text)
end

function types.bool(params)
    return (#params > 0 and params[1].text == "true") or false
end

local function number(params)
    return (#params > 0 and tonumber(params[1].text))
end

function types.int(params)
    return number(params)
end

function types.int32(params)
    return number(params)
end

function types.int64(params)
    return number(params)
end

function types.float(params)
    return number(params)
end

function types.float32(params)
    return number(params)
end

function types.float64(params)
    return number(params)
end

local function unpack_params(params)
    local values = {}
    for _, param in ipairs(params) do
        values[#values+1] = param.children[1].text
    end

    return unpack(values)
end

local Vector3new = Vector3.new
function types.Vector3(params)
    return (#params >= 3 and Vector3new(unpack_params(params)))
end

local CFramenew = CFrame.new
function types.CoordinateFrame(params)
    return (#params >= 3 and CFramenew(unpack_params(params)))
end

function types.ProtectedString(params)
    if #params <= 0 then return end

    local text = params[1].text
    if text:sub(1, 9) == "$$[CDATA[" then
        return text:sub(10, #text-3)
    else
        return text
    end
end

function types.Color3uint8(params)
    if #params <= 0 then return end

end

local function get_properties(xml_node)
    local properties_node = find_first_tag(xml_node, "Properties")
    if not properties_node then return {} end

    local properties = {}
    for _, property_node in ipairs(properties_node.children) do
        local property_name = property_node.attrs.name
        local property_type = property_node.tag

        local func = types[property_type]
        if not func then continue end
        local result, converted_name = func(property_node.children)
        if result ~= nil then
            properties[converted_name or property_name] = result
        end
    end

    return properties
end

local function str(self)
    return getmetatable(self).__properties.Name
end

local instance_table = yoav_instances or {}

local eventual_load = {}

local active_instances = {
    "Script",
    "LocalScript",
    "ModuleScript"
}

local instance_object = {}

local function GetChildren(self)
    return {unpack(getmetatable(self).__children)}
end

instance_object.GetChildren = GetChildren

local function GetDescendants(self, result, level)
    result = result or {}
    level = level or 0

    if level > 100 then
        error("overflow")
    end

    for _, child in ipairs(GetChildren(self)) do
        result[#result+1] = child
        GetDescendants(child, result, level+1)
    end

    return result
end

function instance_object.GetDescendants(self)
    return GetDescendants(self)
end

local function FindFirstAncestor(self, name, level)
    level = level or 0
    if level > 100 then
        error("overflow")
    end
    
    if not self or not self.Name then
        return
    end

    if self.Name == name then
        return self
    else
        return FindFirstAncestor(self.Parent, name, level+1)
    end
end

function instance_object.FindFirstAncestor(self, name)
    assert(name, "Argument 1 missing or nil")
    return FindFirstAncestor(self, name)
end

local function FindFirstAncestorOfClass(self, name, level)
    level = level or 0
    if level > 100 then
        error("overflow")
    end

    if not self or not self.ClassName then
        return
    end
    if self.ClassName == name then
        return self
    else
        return FindFirstAncestorOfClass(self.Parent, name, level+1)
    end
end

function instance_object.FindFirstAncestorOfClass(self, name)
    assert(name, "Argument 1 missing or nil")
    return FindFirstAncestorOfClass(self, name)
end

function instance_object.FindFirstAncestorWhichIsA(self, name)
    assert(name, "Argument 1 missing or nil")
    return FindFirstAncestorOfClass(self, name)
end

function instance_object.FindFirstChild(self, name, recursive)
    assert(name, "Argument 1 missing or nil")
    local searchTable = (recursive and self:GetDescendants()) or self:GetChildren()
    for _, instance in ipairs(searchTable) do
        if instance.Name == name then
            return instance
        end
    end
end

function instance_object.FindFirstChildOfClass(self, name, recursive)
    assert(name, "Argument 1 missing or nil")
    local searchTable = (recursive and self:GetDescendants()) or self:GetChildren()
    for _, instance in ipairs(searchTable) do
        if instance.ClassName == name then
            return instance
        end
    end
end

instance_object.FindFirstChildWhichIsA = instance_object.FindFirstChildOfClass

function instance_object.IsA(self, name)
    assert(name, "Argument 1 missing or nil")
    return self.ClassName == name or self.ClassName == "Instance"
end

local function GetFullName(self, list)
    list = list or {}
    table.insert(list, 1, self.Name)
    if self.Parent == nil then
        return table.concat(list, ".")
    else
        return GetFullName(self.Parent, list)
    end
end

function instance_object.GetFullName(self)
    return GetFullName(self)
end

local function eql(self, value)
    return value == nil
end

local function null()
    return tostring(nil)
end

local function destroy(self)

    if self.kill then
        self:kill()
    end

    local old_metatable = getmetatable(self)
    setmetatable(self, {__eq = eql, __tostring = null})

    local parent = old_metatable.__properties.Parent
    if parent ~= nil then
        local parent_children = getmetatable(parent).__children or {}
        local index = table.find(parent_children, self)
        if index then table.remove(parent_children, index) end
    end

    for _, child in ipairs(old_metatable.__children) do
        if child ~= nil then
            destroy(child)
        end
    end
end

instance_object.Destroy = destroy

local function load(self)
    local source = self.Source
    if not source or getmetatable(self).__thread then return end

    local script_function, error_message = loadstring(source)
    if not script_function then error(string.format("@%s\n %s", GetFullName(self), error_message)) end
    getfenv(script_function).script = self
    local thread = coroutine.create(script_function)

    getmetatable(self).__thread = thread

    local values = {coroutine.resume(thread)}

    if values[1] == false then error(string.format("@%s\n %s", GetFullName(self), values[2]), 0) end

    local returned_values = {}
    for index, v in ipairs(values) do
        if index ~= 1 then
            returned_values[#returned_values+1] = v
        end
    end
    return unpack(returned_values)
end

local function kill(self)
    local thread = getmetatable(self).__thread
    if coroutine.status ~= "dead" then
        coroutine.close(thread)
        getmetatable(self).__thread = nil
    end
end

local function index(self, index)

    local metatable = getmetatable(self)
    
    local children = {}
    for _, child_instance in ipairs(metatable.__children) do
        local name = getmetatable(child_instance).__properties["Name"]
        if name ~= nil then
            children[name] = child_instance
        end
    end

    local child = children[index]
    local custom_method = metatable.__custom_methods[index]
    local instance_method = instance_object[index]
    local property = metatable.__properties[index]
    return child or custom_method or instance_method or property or error(string.format('%s is not a valid member of %s "%s"', index, metatable.__type, metatable.__properties.Name))
end

local function newindex(self, index, value)
    
end

local function create_instance(xml_node, children, parent)

    local custom_methods = {}


    local instance = newproxy(true)
    local metatable = getmetatable(instance)

    metatable.__type = xml_node.attrs.class or "Instance"
    metatable.__tostring = str
    metatable.__index = index
    metatable.__newindex = newindex
    metatable.__children = children
    metatable.__custom_methods = custom_methods
    
    local properties = get_properties(xml_node)

    properties.Parent = parent
    properties.ClassName = metatable.__type

    metatable.__properties = properties

    if table.find(active_instances, metatable.__type) then
        custom_methods.load = load
        custom_methods.kill = kill
    end

    if metatable.__type == "LocalScript" then
        eventual_load[#eventual_load+1] = instance
    end

    instance_table[#instance_table+1] = instance

    return instance
end

local function deepConversion(xml_node, parent_table, parent)
    parent_table = parent_table or {}

    local xml_node_children = xml_node.children
    for _, node in ipairs(xml_node_children) do
        if node.tag ~= "Item" then continue end
        local children_table = {}
        local instance = create_instance(node, children_table, parent)
        deepConversion(node, children_table, instance)
        parent_table[#parent_table+1] = instance
    end
    
    return parent_table
end

return (function(raw_xml)
    assert(raw_xml:sub(1, 8) ~= "<roblox!", ".rbxm and .rbxl files are not supported yet, use rbxmx")
    raw_xml = raw_xml:gsub("<!%[CDATA%[", "$$[CDATA[") -- removes annoyance on ProtectedString

    local success, prased_xml = pcall(xml.parse, raw_xml)
    if not success then error("failed to parse xml") end

    local roblox = find_first_tag(prased_xml, "roblox")
    assert(roblox, "xml file is missing a <roblox> element")


    local converted = deepConversion(roblox)

    for _, script in ipairs(eventual_load) do
        script:load()
    end

    return unpack(converted)
end)
