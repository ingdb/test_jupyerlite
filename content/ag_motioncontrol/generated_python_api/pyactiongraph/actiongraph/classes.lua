local pprint  = require"utils".print
local perror = require"utils".error

local classes = {}
function classes.MakeClass(fields, ...)
    local NewClass = fields or {}
    -- NewClass.__index = NewClass
    

    -- pprint(NewClass)

    local supersMap = {}
    local metafieldsToPropagate = {}
    for _, super in ipairs({...}) do
        if type(super) ~= "table" then 
            perror(super.." is not a table")
        end
        supersMap[super] = true

        local superMT = getmetatable(super) or {}
        for k, v in pairs(superMT) do
            if k ~= "__call" and k ~= "__index" and k~= "__newindex" and k:sub(1, 2) == "__" then
                -- print("SuperClass metafield found: ", k, v)
                if metafieldsToPropagate[k] ~= nil then
                    perror("Superclasses metafield multiple definition: " .. k)
                end

                metafieldsToPropagate[k] = v
            end
        end
    end

    function NewClass:isSubclass(C)
    end

    function NewClass:isInstance(C)
        -- pprint(self, C or "nil", getmetatable(self) or "nil", NewClass, self.__class)
        -- if not (getmetatable(self) == self and self.__class == true) and getmetatable(self).__class ~= true then
        --     pprint("here")
        --     return false
        -- end
        if C == NewClass then
            -- pprint("here")
            return true
        else 
            -- pprint("here")
            for super, _ in pairs(supersMap) do
                -- pprint(self, C or "nil", getmetatable(self) or "nil", NewClass)
                if type(super.isInstance) == "function" then
                    if super:isInstance(C) then
                        -- pprint("here")
                        return true
                    end
                elseif super == C then
                    return true
                elseif getmetatable(super) == C then
                    return true
                end
            end
        end
        return false
    end

    local instanceMT = {
        __index = NewClass,
        __class = NewClass,
        __newindex = function(t, k, v)
            local existing = t[k]
            if existing == nil then
                perror("cannot set unexisting field")
            elseif type(existing) ~= type(v) then
                perror("trying to assign a wrong type")
            end
            rawset(t, k, v)
        end
    }
    instanceMT.__metatable = instanceMT

    for k, v in pairs(metafieldsToPropagate) do
        instanceMT[k] = v
    end
    local classMT = {
        __index = function (t, k)
            for super, _ in pairs(supersMap) do
                local v = super[k]
                if v then 
                    return v 
                end
            end
        end,
        __call = function(self, newObject)
            newObject = newObject or {}
            -- pprint(self, newObject)
            setmetatable(newObject, instanceMT)
            return newObject
        end
    }
    setmetatable(NewClass, classMT)
    -- pprint("class metatable: ", getmetatable(NewClass))
    return NewClass
end

return classes