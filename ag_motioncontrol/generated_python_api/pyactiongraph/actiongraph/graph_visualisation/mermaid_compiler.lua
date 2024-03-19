local P = {}   -- package

local ag_utils = require'interpreter.helpers'
local utils = require'utils'
local log = ag_utils.log
-- log = function()end
local ipairs = ipairs
local pairs = pairs
local OrderedTable = require"orderedtable"
local error = error
local table = table
local string = string
local io = io
local path_lib = require("pl.path")
local templateSubst = require 'pl.template'.substitute

local globalEnv = _ENV
local _ENV = P



function NewMermaidRobotHandler(robot)


    local R = {
        mainContext = robot,
        emitters = {},
        createdNodes = {},
        autoIDMap = {},
        output = ""
    }

    function R:nodeNestingLevel(node)
        local n = 0
        local prnt = node:Parent()
        while prnt do 
            n = n+1
            prnt = prnt:Parent()
        end
        return n
    end

    function R:createMermaidID()
        if self.mermaidIDCounter == nil then
            self.mermaidIDCounter = 0
        end
        self.mermaidIDCounter = self.mermaidIDCounter + 1
        return string.format( "n%s", self.mermaidIDCounter)
    end
    function R:handleGraphRecursively(gr, currentDepth)
        -- log(currentDepth)
        if self.maxDepth and currentDepth > self.maxDepth then  return end
        if self.createdNodes[gr] == nil then
            self.createdNodes[gr] = {
                mermaidID = self:createMermaidID()
            }
        end
        local nameStr = ""
        if gr:ID() ~= "__root_graph" then
            nameStr = "<br/>".."'"..gr:ID().."'"
        end
        if gr.IsBasicType == false then
            self.createdNodes[gr].compound = true
            self:outputLine(string.format("subgraph %s_container[ ]", self.createdNodes[gr].mermaidID))
            self.outputIndent = self.outputIndent + 1
            self:outputLine(string.format('%s["%s%s"]', 
                self.createdNodes[gr].mermaidID,
                gr.TypeAlias or gr.Type,
                nameStr
            ))
            self:outputLine(string.format("class %s containerHeaderClass", self.createdNodes[gr].mermaidID))

            self.mainContext:IterateLogicalEntityChildren(gr, function(e, ...)
                
                R:handleGraphRecursively(e, currentDepth + 1)
                -- self:outputLine("")
            
            end, "Graph")

            if self.createdNodes[gr].additionalChildrenNodes ~= nil then
                for _, n in ipairs(self.createdNodes[gr].additionalChildrenNodes) do
                    self:outputLine(n)
                end
            end
    
     

            self.outputIndent = self.outputIndent - 1
            self:outputLine("end")
            self:outputLine(string.format("class %s_container containerContourClass", self.createdNodes[gr].mermaidID))

            
        else
            self.createdNodes[gr].compound = false
            self:outputLine(string.format('%s("%s%s")', 
                self.createdNodes[gr].mermaidID,
                gr.TypeAlias or gr.Type,
                nameStr
            ))
        end
    end
    function R:makeIndent()
        local r = ""
        local i = self.outputIndent
        while i > 0 do
            r = r .. "  "
            i = i - 1
        end

        return r
    end

    function R:outputLine(l)
        self.output = self.output .. self:makeIndent() .. l .. "\n"
    end

    function R:isNestedInto(gr, potentialParent)
        local toCheck = gr
        while toCheck ~= nil do
            if potentialParent == toCheck then
                return true
            end
            toCheck = toCheck:Parent()
        end
        return false
    end

    function R:findCommonParent(nodes)
        if #nodes == 1 then 
            return nodes[1]:Parent() == nil, nodes[1]:Parent() 
        end

        local currentCommon = nil
        if nodes[1].IsBasicType == true then currentCommon = nodes[1]:Parent()  
        else currentCommon = nodes[1]
        end
        if currentCommon == nil then return true end

        local currentIndex = 2

        while currentIndex ~= #nodes+1 do
            
            local nextNode = nodes[currentIndex]


            while true do
                if self:isNestedInto(nextNode, currentCommon) then
                    break
                elseif self:isNestedInto(currentCommon, nextNode) then
                    currentCommon = nextNode
                    break
                end
                currentCommon = currentCommon:Parent()
                if currentCommon == nil then return true end
            end
            currentIndex = currentIndex + 1
        end
        return currentCommon == nil, currentCommon
    end


    function R:run(maxDepth)
        self.createdNodes = {}
        self.createdParams = {}
        self.createdHWModules = {}
        self.outputIndent = 0
        self.outputNodesTree = {}
        self.currentOutputNode = self.outputNodesTree
        self.maxDepth = maxDepth
      
        self:outputLine("flowchart TB;")
        self:outputLine("")
        -- self:outputLine("classDef containerHeaderClass fill:#333,stroke-width:0px;")
        self:outputLine("classDef containerHeaderClass stroke-width:0px;")
        self:outputLine("classDef hiddenDetailsClass fill:#555,stroke-width:0px,color:#888;")
        self:outputLine("classDef containerContourClass stroke-width:2px;")
        self:outputLine("classDef joinBlockClass fill:#00000000,stroke-width:1px;")

        local rootGraph = self.mainContext:GlobalEntity("Graph")
        if rootGraph == nil then
            log("No graph")
        end


        

        local connections = rootGraph:GatherConnections()
        for connIndex, conn in ipairs(connections) do
            -- log("\n\n####### ", connIndex, " ######" )

            local srcNodes = {}
            local dstNodes = {}
            local allHidden = true

            local allNodes = {}

            for _, event in ipairs(conn.ResolvedEvents) do               
                table.insert( srcNodes, event:Parent() )
                table.insert( allNodes, event:Parent() )
            end

            for _, slot in ipairs(conn.ResolvedSlots) do               
                table.insert( dstNodes, slot:Parent() )
                table.insert( allNodes, slot:Parent() )
            end


            local commonIsRoot, commonParent = self:findCommonParent(allNodes)

            -- log("Common root", commonIsRoot, commonParent)
            -- if commonIsRoot == true then 
            --     for _, n in ipairs(allNodes) do
            --         log("  ", n)
            --     end
            -- end

            local hiddenDetailsNodeNeeded = false
            local hiddenDetailsID = (self.createdNodes[commonParent] or {}).hiddenDetailsNode or self:createMermaidID()

            for _, slot in ipairs(conn.ResolvedSlots) do
                local dstNode = slot:Parent()
               
                if self.maxDepth and self:nodeNestingLevel(dstNode) > self.maxDepth then
                    hiddenDetailsNodeNeeded = true
                    self.createdNodes[dstNode] = {
                        mermaidID = hiddenDetailsID,
                        hidden = true
                    }
                else
                    -- log("HERE", slot)
                    allHidden = false
                    if self.createdNodes[dstNode] == nil then
                        self.createdNodes[dstNode] = {
                            mermaidID = self:createMermaidID(),
                            hidden = false
                        }
                    end 
                end
            end

            for _, event in ipairs(conn.ResolvedEvents) do
                local srcNode = event:Parent()

                if self.maxDepth and self:nodeNestingLevel(srcNode) > self.maxDepth then
                    hiddenDetailsNodeNeeded = true
                    self.createdNodes[srcNode] = {
                        mermaidID = hiddenDetailsID,
                        hidden = true
                    }
                else
                    -- log("HERE", event)
                    allHidden = false
                    if self.createdNodes[srcNode] == nil then
                        self.createdNodes[srcNode] = {
                            mermaidID = self:createMermaidID(),
                            hidden = false
                        }
                    end 
                end
            end
            
            if allHidden == true then 
                -- log("All hidden") 
            else 
                -- log("SOMETHING VISIBLE")
            end
            if allHidden == false and #conn.ResolvedEvents == 1 then
                local event = conn.ResolvedEvents[1]

                local srcNode = event:Parent()
                local mermaidSrcID = self.createdNodes[srcNode].mermaidID
              
                local connStrLeft = ""

                if event:ID() == "started" then
                    connStrLeft = "-.-"
                elseif event:ID() == "stopped" then
                    connStrLeft = "--"
                else
                    connStrLeft = "-- "..event:ID().."--"
                end

                local connStrRight = ""

                for _, slot in ipairs(conn.ResolvedSlots) do
                    local dstNode = slot:Parent()
                    if slot:ID() == "start" then
                        connStrRight = ">"
                    elseif slot:ID() == "stop" then
                        connStrRight = "x"
                    else
                        connStrRight = "o"
                    end
                    local dstID = self.createdNodes[dstNode].mermaidID
                    -- log("connection to", self.createdNodes[dstNode].mermaidID)

                    local actualSrcID = mermaidSrcID
                    if self.createdNodes[srcNode].hidden == false and srcNode.IsBasicType == false and self:isNestedInto(dstNode, srcNode) == false then
                        actualSrcID = actualSrcID .. "_container"
                        -- log("overriden to container src")
                    end

                    if self.createdNodes[dstNode].hidden == false and dstNode.IsBasicType == false and self:isNestedInto(srcNode, dstNode) == false then
                        dstID = dstID .. "_container"
                        -- log("overriden to container dst")
                    end
    
                 
                    self:outputLine(string.format( "%s %s%s %s",
                        actualSrcID,   
                        connStrLeft,
                        connStrRight,
                        dstID
                    ))
                end
            elseif allHidden == false then
                local allSrcHidden = true
                for _, event in ipairs(conn.ResolvedEvents) do
                    if self.createdNodes[event:Parent()].hidden == false then
                        allSrcHidden = false
                        break
                    end
                end
                local joinBlockID = self:createMermaidID()
                local jType = ""
                if conn.IsAnyEvent then jType = "{OR}" else jType = '(("AND"))' end

              
                
                if commonIsRoot == true then
                    self:outputLine(string.format( "%s%s",
                        joinBlockID,
                        jType
                    ))
                    self:outputLine(string.format("class %s joinBlockClass", joinBlockID))

                else
                    if self.createdNodes[commonParent] == nil then
                        self.createdNodes[commonParent] = {
                            mermaidID = self:createMermaidID()
                        }
                    end 
                    if self.createdNodes[commonParent].additionalChildrenNodes == nil then
                        self.createdNodes[commonParent].additionalChildrenNodes = {}
                    end
                    if allSrcHidden == false then
                        table.insert(self.createdNodes[commonParent].additionalChildrenNodes, 
                            string.format( "%s%s",
                                joinBlockID,
                                jType
                            )
                        )
                        table.insert(self.createdNodes[commonParent].additionalChildrenNodes, 
                        string.format("class %s joinBlockClass", joinBlockID)
                    )
                    else
                        joinBlockID = hiddenDetailsID
                    end
                end
                local joinedConnStr = ""
                if allSrcHidden == false then
                    local connStrLeft = ""
                    for _, event in ipairs(conn.ResolvedEvents) do
                        local srcNode = event:Parent()
                        if event:ID() == "started" then
                            connStrLeft = "-.-"
                        elseif event:ID() == "stopped" then
                            connStrLeft = "---"
                        else
                            connStrLeft = "--- "..event:ID().." ---"
                        end
                    
                        local actualSrcID = self.createdNodes[srcNode].mermaidID
                        if self.createdNodes[srcNode].hidden == false and srcNode.IsBasicType == false then
                            actualSrcID = actualSrcID .. "_container"
                            -- log("overriden to container src")
                        end
    

                        self:outputLine(string.format( "%s %s %s",
                            actualSrcID,
                            connStrLeft,
                            joinBlockID
                        ))
                    end    
                    joinedConnStr = "=="       
                else
                    joinedConnStr = "--"     
                end    
                local connStrRight = ""   
                for _, slot in ipairs(conn.ResolvedSlots) do
                    local dstNode = slot:Parent()
                    if slot:ID() == "start" then
                        connStrRight = ">"
                    elseif slot:ID() == "stop" then
                        connStrRight = "x"
                    else
                        connStrRight = "o"
                    end
                    local nextID = self.createdNodes[dstNode].mermaidID
                 

                    self:outputLine(string.format( "%s %s%s %s",
                        joinBlockID,
                        " " .. joinedConnStr,
                        connStrRight,
                        nextID
                    ))
                end
            end           
            if hiddenDetailsNodeNeeded == true then

                if commonIsRoot == true then
                    self:outputLine(string.format( "%s{{Hidden}}", hiddenDetailsID))
                    self:outputLine(string.format("class %s hiddenDetailsClass", hiddenDetailsID))

                else
                    if self.createdNodes[commonParent] == nil then
                        self.createdNodes[commonParent] = {
                            mermaidID = self:createMermaidID()
                        }
                    end 
                    if self.createdNodes[commonParent].additionalChildrenNodes == nil then
                        self.createdNodes[commonParent].additionalChildrenNodes = {}
                    end
                    if self.createdNodes[commonParent].hiddenDetailsNode == nil then
                        self.createdNodes[commonParent].hiddenDetailsNode = hiddenDetailsID
                        table.insert(self.createdNodes[commonParent].additionalChildrenNodes, 
                                string.format( "%s{{Hidden}}", hiddenDetailsID)
                        )
                        table.insert(self.createdNodes[commonParent].additionalChildrenNodes, 
                                string.format( "class %s hiddenDetailsClass", hiddenDetailsID)
                        )
                    end
                end

            end
           
        end
   
        self:handleGraphRecursively(rootGraph, 0)

       
        return self.output
    end
   
    return R
end
function NewMermaidCompiler()
    local R = {}
    R.htmlTemplate = [[
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        </head>
        <body>
# for robotid , src in pairs(mermaidSrc) do
        <h1>$(robotid)</h1>
        <div class="mermaid">
            $(src)
        </div>
        </br>
# end
        <script>
            $(mermaidLibraryCode)
        </script>
        <script>
            mermaid.initialize({
                startOnLoad:true,
                securityLevel: 'loose',
                theme: 'dark',
                curve: 'basis'
            });
        </script>
        </body>
        </html>
]]
    function R:SaveResult(mermaidCode, outputfile)
            
        if mermaidCode == nil then
            error("No mermaid output")
        end

        local ext = path_lib.extension(outputfile)
        if ext == ".md" then
            local file = io.open(outputfile, "w")
            for id, code in pairs(mermaidCode) do
                file:write("# "..id.."\n")
                file:write("```mermaid\n"..code.."\n```")
            end
            file:close()
        elseif ext == ".html" then
            if self.mermaidLibraryCode == nil then
                local p = path_lib.join(ag_utils.currentSourceFilePath(), "mermaid.min.js")
                local file = io.open(p, 'r')
                if file == nil then error("Cannot open mermaid lib file: "..p) end
                self.mermaidLibraryCode = file:read("a")
                file:close()
            end
            local out, err = templateSubst(self.htmlTemplate, {
                mermaidSrc=mermaidCode,
                mermaidLibraryCode = self.mermaidLibraryCode, 
                pairs = pairs
            })
            if out == nil then
                utils.print("Template error", err)
            end
            local file = io.open(outputfile, "w")
            if file == nil then 
                utils.errorExt("Cannot open output file: ", outputfile)
            end
            file:write(out)
            file:close()

        else
            error("unsupported mermaid output")
        end

        return R
    end

    function R:run(context, maxDepth, outputfile)
        local outputs = {}

        for id, robot in pairs(context.Robots) do
            local cmp = NewMermaidRobotHandler(robot)
            local code = cmp:run(2)
            outputs[id] = code
        end
        self:SaveResult(outputs, outputfile)

    end
    return R
end

return P
