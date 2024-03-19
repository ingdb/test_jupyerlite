local utils = require("utils")
local coromake = require "coroutine.make"
local coroutine = coromake("___ag_scheduler____")
local OrderedTable = require"orderedtable"

local scheduler = {
    tasks_list = {},
    pending_events = {},
    tasks_to_add = {},
    inside_tick = false,
    finished_callback = function() end,

    pollingTimers = {}
}

scheduler.ErrorMT = {
    __tostring = function(self)
        local ret = ""
        for tag, _ in pairs(self.tags) do
            ret = ret .. tag.text .. " "
        end
        if type(self.data) ~= "table" then ret = ret .. "\n" .. tostring(self.data)
        else
            for k, v in pairs(self.data) do
                ret = ret .. "\n" .. k .. " " .. tostring(v)
            end
        end
        return ret
    end
}
function scheduler.pushEvent(task_id, ...)
    local task = scheduler.tasks_list[task_id]
    local task_label = "n/a"
    if task ~= nil then 
        task_label = task.label
    else
        local i = 3
        local info = debug.getinfo(i)

        local n = ""
        if info.name and info.name ~= "?" then n = ": "..info.name end
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" 
        elseif src:sub(1,1) == "@" then src = src:sub(2) end
        local line = info.currentline or "n/a"

        utils.print("Scheduler Warning! Trying to push event for unexisting task from "..src .. ":" .. line .. n)
    end
    table.insert(scheduler.pending_events, {ok = true, task_to_continue_key = task_id, data = {...}, task_label = task_label})
end

function scheduler.pushError(task_id, errorTags, ...)
    local task = scheduler.tasks_list[task_id]
    local task_label = "n/a"
    if task ~= nil then 
        task_label = task.label 
    else
        local i = 2
        local info = debug.getinfo(i)

        local n = ""
        if info.name and info.name ~= "?" then n = ": "..info.name end
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" 
        elseif src:sub(1,1) == "@" then src = src:sub(2) end
        local line = info.currentline or "n/a"

        utils.print("Scheduler Warning! Trying to push error for unexisting task from "..src .. ":" .. line .. n)
    end
    table.insert(scheduler.pending_events, {ok = false, task_to_continue_key = task_id, data = setmetatable({tags=errorTags, data = {...}}, scheduler.ErrorMT), task_label = task_label})
end

scheduler.TASK_CANCELLED = {text = "TASK_CANCELLED"}
scheduler.EXTERNAL_EXCEPTION = {text = "EXTERNAL_EXCEPTION"}
scheduler.USER_CODE_EXCEPTION = {text = "USER_CODE_EXCEPTION"}

function scheduler.tick()
    -- utils.print("tick") -- TODO remove me
    if scheduler.inside_tick then
        return "Internal scheduler error 0"
    end
    scheduler.inside_tick = true
    local queue = OrderedTable()
    local toRemove = {}
    for coro, task_to_handle in pairs(scheduler.tasks_list) do
        if coroutine.status(task_to_handle.task) == "dead" then
            table.insert(toRemove, coro)
        else
            if task_to_handle.awaits == false then
                queue[task_to_handle] = {ok=true, data={true}}
            end
        end
    end
    for _, k in ipairs(toRemove) do
        -- coroutine.close(task_to_handle.task)
        scheduler.tasks_list[k] = nil
    end
    do
        for _, event in ipairs(scheduler.pending_events) do
            local task_to_continue_key = event.task_to_continue_key
            local task_to_continue = scheduler.tasks_list[task_to_continue_key]
            if task_to_continue == nil or task_to_continue.erred == true then
                if task_to_continue == nil  then
                    utils.print(string.format("WARNING: unexisting target task '%s' for event", event.task_label))
                else
                    utils.print(string.format("WARNING: erred target task '%s' for event '%s'", task_to_continue.label, event))
                end
            elseif task_to_continue ~= nil then
                local ignoreEvent = false
                if queue[task_to_continue] ~= nil then
                    local oldEvent = queue[task_to_continue]
                    local newEvent = event
                    if type(oldEvent.data) == "table" and getmetatable(oldEvent.data) == scheduler.ErrorMT and oldEvent.data.tags[scheduler.TASK_CANCELLED] then
                        if task_to_continue.debug then
                            utils.print("Ignoring event as already had cancel event: ", task_to_continue.label)
                        end
                        ignoreEvent = true
                    elseif type(newEvent.data) == "table" and getmetatable(newEvent.data) == scheduler.ErrorMT and newEvent.data.tags[scheduler.TASK_CANCELLED] then
                        if task_to_continue.debug then
                            utils.print("Overriding event since new event is cancel event", task_to_continue.label)
                        end
                        queue[task_to_continue] = event
                        ignoreEvent = true
                    else
                        return "Multiple events to same task in single tick"
                    end
                end
                if ignoreEvent == false then
                    if task_to_continue.awaits ~= true then
                        utils.print(tostring(event.data))
                        for k, v in pairs(event.data) do
                            utils.print(k, v)
                        end
                        return "Event to non-waiting task: "..task_to_continue.label.." "..tostring(event.ok)
                    end
                    if coroutine.status(task_to_continue.task) ~= "suspended" then
                        return "Event to non-suspended task"
                    end
                    task_to_continue:setAwaits(false)
                    
                    queue[task_to_continue] = event
                end
            else
                return "Internal scheduler error 3"
            end
        end
        scheduler.pending_events = {}
    end

    for task_to_handle, event in pairs(queue) do
        if task_to_handle.debug then
            utils.print(string.format("Resuming task '%s' with event data '%s', ok=%s", task_to_handle.label, event.data, event.ok))
        end
        local status, res = coroutine.resume(task_to_handle.task, event.data, event.ok)
        task_to_handle.started = true
        if status == false then
            if type(res) ~= "table" or res.tags == nil or getmetatable(res) ~= scheduler.ErrorMT then
                return "Internal scheduler error 4"
            else
                if res.tags[scheduler.TASK_CANCELLED] == nil then
                    utils.print(string.format("Error in task '%s': %s", task_to_handle.label, res))
                else
                    if task_to_handle.debug then
                        utils.print(string.format("Task '%s' correctly thrown a error because cancelled", task_to_handle.label))
                    end
                end
            end
            
            task_to_handle.errorData = res
            task_to_handle.erred = true
            task_to_handle:setAwaits(false)
        end
        if coroutine.status(task_to_handle.task) == "dead" then
            -- coroutine.close(task_to_handle.task)
            scheduler.tasks_list[task_to_handle.task] = nil
        end
    end
    local r_count = 0
    local active_count = 0

    for _, new_task in ipairs(scheduler.tasks_to_add) do
        scheduler.tasks_list[new_task.task] = new_task
    end
    scheduler.tasks_to_add = {}

    toRemove = {}
    for coro, task_to_handle in pairs(scheduler.tasks_list) do
        if coroutine.status(task_to_handle.task) == "dead" then
            table.insert(toRemove, coro)
        else
            r_count = r_count + 1
            -- utils.print("running", task_to_handle.label)
            if task_to_handle.awaits == false or task_to_handle.started == false then 
                active_count = active_count + 1
            end
        end
    end
    for _, k in ipairs(toRemove) do
        -- coroutine.close(task_to_handle.task)
        scheduler.tasks_list[k] = nil
    end

    local tickersToRemove = {}
    for ticker, _ in pairs(scheduler.pollingTimers) do
        if not ticker() then
            table.insert(tickersToRemove, ticker)
        end
    end
    for _, i in ipairs(tickersToRemove) do
        -- utils.print("removing timer")
        scheduler.pollingTimers[i] = nil
    end

    scheduler.inside_tick = false

    local pending_events_count = 0
    do
        pending_events_count = #scheduler.pending_events
    end
    return nil, r_count, active_count, pending_events_count
end

function scheduler.run(runUntilPredicate, high_perf_mode)

    local prev_r_count = 0
    while true do
        local ts = millis()

        local err, r_count = scheduler.tick()
        if err ~= nil then
            utils.errorExt(err)
        end

        if r_count == 0 then
            utils.print("All tasks are finished, exiting the loop")
            break
        end

        if r_count ~= prev_r_count then
            -- utils.print("Resumed count", r_count)
            prev_r_count = r_count
        end

        if high_perf_mode ~= true and millis() - ts < 1 then
            delay(1)
        end
        if type(runUntilPredicate) == "function" then
            if not runUntilPredicate() then
                break
            end
        end
    end
end
local prev_r_count = 0
local prev_active_count = 0
function scheduler.runUntilNoActive()
    -- utils.print("runUntilNoActive")
    while true do
        local err, r_count, active_count, pending_events_count = scheduler.tick()
        -- utils.print(err or "no err", r_count, active_count, pending_events_count)
        if err ~= nil then
            utils.errorExt(err)
        end

        if r_count == 0 then
            scheduler.finished_callback()
            return false
        end
        if prev_active_count ~= active_count then
            -- print("prev_active_count", active_count)
            prev_active_count = active_count
        end
        if active_count == 0 and pending_events_count == 0 then
            if r_count ~= prev_r_count then
                -- print("r_count", r_count)
                prev_r_count = r_count
            end
            return true
        end
    end
end

function scheduler.print_running()
    utils.print("\n\n\nDEBUG printing all running tasks")
    for coro, task_to_handle in pairs(scheduler.tasks_list) do
        if coroutine.status(task_to_handle.task) == "dead" then
           
        else
            utils.print(task_to_handle.label)
        end
    end
end

-- should never be called from outside! return 2 values: 'ok' and 'data'. If ok is true, need to pass control to task. If not, need to throw error with 'data' inside.
function scheduler.yield()
    -- [[ TODO
    local t = scheduler.tasks_list[coroutine.running ()]
    if t.awaits ~= true then
        utils.print("Warning, yielded task", t.label, "without set wait state")
    end
    --]]
    return coroutine.yield()
end

local function catchUserCodeError(clb)
    local ok, result = pcall(clb)
    if ok == false then
        if type(result) == "table" and getmetatable(result) == scheduler.ErrorMT then
            error(result)
        end
        
        local errObject = {
            tags = {[scheduler.USER_CODE_EXCEPTION] = true},
            data = result
        }
        error(setmetatable(errObject, scheduler.ErrorMT))
    end
end

function scheduler.addTask(f, label, debug_output)
    debug_output = debug_output or false
    label = label or ""
    local i = 2
    local info = debug.getinfo(i)

    local n = ""
    if info.name and info.name ~= "?" then n = ": "..info.name end
    local src = info.source or "n/a"
    if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" 
    elseif src:sub(1,1) == "@" then src = src:sub(2) end
    local line = info.currentline or "n/a"
    label = label.."("..src .. ":" .. line .. n..")"

    if type(f) ~= "function" then
        utils.errorExt("task should be a function")
    end
    local t = coroutine.create(function()catchUserCodeError(f) end)
    local newTask = {
        task = t,
        label = label or "anonymous",
        awaits = false,
        started = false,
        debug = debug_output
    }
    function newTask:setAwaits(val)
        self.awaits = val
        if self.debug then
            
            local errTxt = ""
            for iii=2,20 do
                local info = debug.getinfo(iii)
                if info == nil then break end
        
                local n = info.name or "n/a"
                local src = info.source or "n/a"
                if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
                local line = info.currentline or "n/a"
                errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
          
            end
            utils.print("Task '"..self.label.."' awaits: "..tostring(self.awaits)..'\n'..errTxt)

        end
    end
    table.insert(scheduler.tasks_to_add, newTask)
    return {
        task = newTask,
        cancel = function()
            -- coroutine.close(t)
            
            if scheduler.tasks_list[t] and scheduler.tasks_list[t].erred ~= true then
                if newTask.debug then
                    local errTxt = ""
                    for iii=2,20 do
                        local info = debug.getinfo(iii)
                        if info == nil then break end
                
                        local n = info.name or "n/a"
                        local src = info.source or "n/a"
                        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
                        local line = info.currentline or "n/a"
                        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
                
                    end

                    utils.print("Cancelling '"..newTask.label.."' from\n"..errTxt)
                end
                if newTask.externalCanceller ~= nil then
                    -- utils.print("calling externalCanceller")
                    newTask.externalCanceller()
                end
                scheduler.pushError(t, {[scheduler.TASK_CANCELLED] = true})
                -- if not scheduler.inside_tick then -- to check if we are still in Lua domain
                --     scheduler.runUntilNoActive()
                -- end
            else
                if scheduler.tasks_list[t] ~= nil then
                    local errTxt = ""
                    for iii=2,20 do
                        local info = debug.getinfo(iii)
                        if info == nil then break end
                
                        local n = info.name or "n/a"
                        local src = info.source or "n/a"
                        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
                        local line = info.currentline or "n/a"
                        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
                
                    end
                
                    utils.print(string.format("Task '%s' cannot be cancelled\n%s", newTask.label,errTxt))
                end
            end
        end
    }
end

function scheduler.pollingCallAfter(resolve, _, s)
    if s < 0 then s = 0 end
    local fireAt = millis() + s * 1000
    local cancelled = false
    local timer = function()
        if millis() > fireAt and not cancelled then
            -- utils.print("here")
            resolve()
            return false
        end
        return true
    end
    scheduler.pollingTimers[timer] = true
    return function() 
        scheduler.pollingTimers[timer] = nil
        cancelled = true
        -- utils.print("Polling timer cancelled")
    end
end

function scheduler.callAsyncFunctionWithCallback(f, resolve, reject, ...)
    local args = {...}
    scheduler.addTask(function()
        local ok, err = pcall(function()
            local ret = {f(table.unpack(args))}
            resolve(ret)
        end)
        if not ok then
            utils.print(err)
            reject(err)
        end
    end)
end
function scheduler.waitExternalEvent(eventSetuper, ...)
    local r = coroutine.running ()
    local task = scheduler.tasks_list[r]
    if task  == nil then
        utils.errorExt("FFFUU")
        return
    end
    task:setAwaits(true)
    local canceller = eventSetuper(
        function(...)
            scheduler.pushEvent(r, ...)
            -- if scheduler.inside_tick then -- to check if we are still in Lua domain
            --     return
            -- end
            -- return scheduler.runUntilNoActive() -- ???? what if event is pushed from another thread?
        end, 
        function(...)
            scheduler.pushError(r, {[scheduler.EXTERNAL_EXCEPTION] = true}, ...)
            -- if scheduler.inside_tick then -- to check if we are still in Lua domain
            --     return
            -- end
            -- return scheduler.runUntilNoActive() -- ???? what if event is pushed from another thread?
        end, 
        ...)
    if task.externalCanceller ~= nil then
        utils.error("FFFUU")
    end
    task.externalCanceller = canceller
    local continueData, ok = scheduler.yield()
    task.externalCanceller = nil
    if ok == true then
        return table.unpack(continueData)
    else
        error(continueData, 2);
    end
end

function scheduler.sleep(s)
    scheduler.waitExternalEvent(scheduler.pollingCallAfter, s)
end

function scheduler.waitEventWithTimeout(event, timeout)
    local timedOut = false
    local timeoutTask = scheduler.addTask(function()
        scheduler.sleep(timeout)
        event:set()
        timedOut = true
    end, string.format("Event '%s' waiter", event))
    event:wait()
    if not timedOut then
        timeoutTask.cancel()
    end
    return not timedOut
end

function scheduler.NewLock()
    local lock = {}
    lock.__locked = false
    lock.__awaiting_list = {}
    
    
    function lock:aquire()
        while self.__locked do
            local r = coroutine.running ()
            if scheduler.tasks_list[r] == nil then
                utils.errorExt("internal scheduler error")
            end
            table.insert(self.__awaiting_list, r)
            scheduler.tasks_list[r]:setAwaits(true)
            local continueData, ok = scheduler.yield()
            if ok == false then
                error(continueData, 2);
            end
        end
        self.__locked = true
    end

    function lock:release()
        if self.__locked == false then
            utils.errorExt("Cannot release unaquired Lock")
        end
        self.__locked = false
        if #self.__awaiting_list > 0 then
            while #self.__awaiting_list > 0 do
                local to_continue = table.remove(self.__awaiting_list, 1)
                if scheduler.tasks_list[to_continue] ~= nil then
                    scheduler.pushEvent(to_continue)
                    break
                end
            end
        end
    end

    function lock:locked()
        return self.__locked
    end

    return lock
end


function scheduler.NewEvent()
    local event = {
        __set = false,
        __awaiting_list = {}
    }
    function event:set()
        self.__set = true

        while #self.__awaiting_list > 0 do
            local to_continue = table.remove(self.__awaiting_list, 1)
            if scheduler.tasks_list[to_continue] ~= nil then
                scheduler.pushEvent(to_continue)
            end
        end
    end

    function event:clear()
        self.__set = false
    end

    function event:is_set()
        return self.__set
    end

    function event:wait()
        if self.__set == false then
            local r = coroutine.running ()
            if scheduler.tasks_list[r] == nil then
                utils.errorExt("internal scheduler error")
            end
            table.insert(self.__awaiting_list, r)
            scheduler.tasks_list[r]:setAwaits(true)
            local continueData, ok = scheduler.yield()
            if ok == false then
                error(continueData, 2);
            end
        end
    end
    return event
end

function scheduler.NewQueue()
    local q = {
        __event = scheduler.NewEvent(),
        __q = {}
    }

    function q:get()
        if #self.__q == 0 then
            self.__event:wait()
            self.__event:clear()
        end

        return table.remove(self.__q, 1)
    end

    function q:put(obj)
        self.__event:set()
        table.insert(self.__q, obj)
    end

    return q
end


return scheduler
