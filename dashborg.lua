#!/usr/bin/lua5.1

-- launch new terminal if not already in one
-- note that this rather hackily REQUIRES something like urxvtd due to the lack of exec in Lua
if not (arg[1] == "--noterm") then
    os.execute("urxvtc -name dashborg -e "..arg[0].." --noterm")
    os.exit()
end

--os.execute("sleep 0.25")

require('io')
require('curses')
local cjson = require('cjson').new()

-- MVP needs:
-- alarm or otherwise notify due stuff

TASK_COMMAND='task'

-- Global utils --
-- ------------ --
function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function ckBinding(key, binding)
    key=key or 0
    for i, v in ipairs(binding) do
        v=v or ""

--        io.stderr:write("key="..key.." binding="..v.."\n")
        if type(v)=="string" and key < 255 then
--            io.stderr:write("key="..string.char(key).." binding="..v.."\n")
            if(string.char(key))=="[" then key=63 end
            if v:find(string.char(key)) then
                return true
            end
        elseif type(v)=="number" and key==v then
--            io.stderr:write("number eq")
            return true
        end
    end
    return false
end

function execTask(...)
    local cmd = TASK_COMMAND..' '..table.concat({...}, ' ')
--    io.stderr:write(cmd.."\n")
    local f = io.popen(cmd)
--    os.execute("sleep 0.1")
    local r = nil
    repeat
        -- keep trying until we get something
        r = f:read("*a")
    until r
    return r
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function reread()
    local tasks = {}
--    for k,v in pairs(cjson.decode('['..execTask('status.not:deleted', 'status.not:completed', 'status.not:waiting', 'export')..']')) do
    local ids = trim(execTask("ids"))
    for k,v in pairs(cjson.decode('['..execTask(ids, "status.not:waiting", "export")..']')) do
        tasks[k] = Task:new(v)        
    end
    return tasks
end

function fill(window, left, top, w, h, letter)
    for x = left, left+w-1, 1 do
        for y = top, top+h-1, 1 do
            window:mvaddch(y, x, letter)
        end
    end
end

--TODO: actually handle default value
function promptStr(prompt, default)
    local bottom, right = stdscr:getmaxyx()
    bottom = bottom-1
    
    curses.attrset(curses.color_pair(COLOR_PROMPTROW))
    stdscr:mvhline(bottom, 0, ' ', right)
    stdscr:mvaddstr(bottom, 0, prompt..": ")
    stdscr:refresh()
    needRefresh = true
    curses.echo(true)
    curses.curs_set(1)
    local result = stdscr:mvgetstr(bottom, #prompt+2)
    curses.curs_set(0)
    curses.echo(false)
    curses.attrset(0)
    stdscr:mvhline(bottom, 0, ' ', right)
    return result
end

function feedback(...)
    --promptStr(message)
    local message = table.concat({...}, '\t')
    if true then
        local bottom, right = stdscr:getmaxyx()
        bottom = bottom-1
        
        curses.attrset(curses.color_pair(COLOR_FEEDBACK))
        stdscr:mvhline(bottom, 0, ' ', right)
        stdscr:mvaddstr(bottom, 0, message)
        stdscr:refresh()
        curses.attrset(0)   
        needRefresh = false
    end
end

function registerFollowTarget(x, y, callback)
    followTargets[#followTargets+1] = {["x"]= x, ["y"]= y, ["cb"]= callback}
end

function redraw()
    if needRefresh then
        followTargets = {}

        local h, w = stdscr:getmaxyx()
        -- h-1 to leave a line at the bottom for the feedback row.
        -- Should really do this using curses windows.
        theList:draw(stdscr, 0, 0, w, h-3)
        stdscr:refresh()
    end
end

function getKey(allowReread)
    local c = nil

    while not c do
        c = stdscr:getch()

        if c == curses.KEY_RESIZE then
            needRefresh = true
            redraw()
            c = nil
        end
    end    

    return c
end

-- List class --
-- ---------- --

List = {}
function List:new(items, window)
    local list = {}
    setmetatable(list, self)
    self.__index = self

    list.items = items
    list.selectedIdx = nil
    list.scroll = 0
    return list
end

function List:draw(window, x, y, w, h)
    local i=0
    local yMax = y+h
    for k,v in pairs(self.items) do        
        if i%2 == 1 then
            curses.attrset(curses.color_pair(COLOR_ODDROW))
        end
        if i==self.selectedIdx then
            curses.attrset(curses.color_pair(COLOR_SELECTION))
        end
        i = i+1
        if i >  self.scroll then 
            local idx = i-1
            registerFollowTarget(x, y, function() self.selectedIdx = idx end)
            y = y+v:draw(window, x, y, w, yMax-y)
        end
        curses.attrset(0)
        if y >= yMax then break end
    end

    if y < yMax then for curY = y, yMax, 1 do
        window:mvhline(curY, x, ' ', w)
        window:mvaddch(curY, x, '~')
    end end

    self.lastVisibleIdx = i-1
end

function List:handleKey(ch)
    if ckBinding(ch, bindings.NEXT) and self.selectedIdx < #self.items-1 then
        self.selectedIdx = self.selectedIdx+1
        needRefresh = true        
    elseif ckBinding(ch, bindings.PREV) and self.selectedIdx > 0 then
        self.selectedIdx = self.selectedIdx-1
        needRefresh = true
    else
        needRefresh = false
        return ch    
    end

    if self.selectedIdx < self.scroll then self.scroll = self.selectedIdx end
    if self.lastVisibleIdx and self.selectedIdx > self.lastVisibleIdx then self.scroll = self.scroll+1 end

    return nil
end

function List:getSelectedItem()
    local i=0
    for k,v in pairs(self.items) do
        if i==self.selectedIdx then
            return v
        end
        i = i+1
    end
    return nil
end
        
-- Task class --
-- ---------- --

local tasks = {}

Task = {}

function Task:new(json)
    json = json or {}
    setmetatable(json, self)
    self.__index = self
    return json
end

function Task:measure(width)
    return 1+(self.annotations and #self.annotations or 0)
end

function Task:draw(window, x, y, w, h)
    local height = 1
    local mode = nil
    if self.urgency+0 > 5 then mode = curses.A_BOLD end
    if self.urgency+0 > 8 then mode = curses.A_BLINK end
    if mode then window:attron(mode) end
    window:mvhline(y,x, ' ', w)    
    window:mvaddstr(y, x, string.sub(self.urgency, 0, 4), mode)
    window:mvaddstr(y, x+5, self.description, mode)
    if self.annotations then for k,v in pairs(self.annotations) do        
        window:mvhline(y+height, x, ' ', w)
        window:mvaddstr(y+height, x+4, v.entry.." "..v.description)
        height = height+1
        if height > h then break end
    end end
    return height
end


-- Main --
-- ---- --
print("initing curses...")
curses.initscr()
curses.raw(true)
curses.echo(false)  -- not noecho !
curses.nl(false)    -- not nonl !
curses.halfdelay(5)
curses.curs_set(0)
curses.start_color()
COLOR_ODDROW = 1
curses.init_pair(COLOR_ODDROW, curses.COLOR_WHITE, curses.COLOR_BLUE) 
COLOR_SELECTION = 2
curses.init_pair(COLOR_SELECTION, curses.COLOR_WHITE, curses.COLOR_RED) 
COLOR_PROMPTROW = 3
curses.init_pair(COLOR_PROMPTROW, curses.COLOR_YELLOW, curses.COLOR_BLACK) 
COLOR_FEEDBACK = 4
curses.init_pair(COLOR_FEEDBACK, curses.COLOR_YELLOW, curses.COLOR_BLACK) 
COLOR_FOLLOWTARGET = 5
curses.init_pair(COLOR_FOLLOWTARGET, curses.COLOR_WHITE, curses.COLOR_RED) 
stdscr = curses.stdscr()  -- it's a userdatum
stdscr:clear()
stdscr:keypad(true)
--stdscr:mvaddstr(15,20,'print out curses table (y/n) ? ')

bindings = {}
bindings.PREV = {"k", curses.KEY_UP}
bindings.NEXT = {"j", curses.KEY_DOWN}
bindings.DELETE = {"d"}
bindings.DONE = {"x"}
bindings.PROCRASTINATE = {"p"}
bindings.FOLLOW = {"f"}
bindings.ADD = {"a"}
bindings.DUE = {"b"}
bindings.EDIT = {"e"}
bindings.REREAD = {"r"}


ftLetters = "qwertyuiopasdfghjklzxcvbnm0123456789QWERTYUIOPASDFGHJKLZXCVBNM"

theList = List:new(reread())
local c = nil
local ch = nil
needRefresh = true
followTargets = {}
local handler = nil

theList.selectedIdx = 0

while not ckBinding(ch, {"q"}) do
    redraw()

    ch = getKey()

    local bubble = theList:handleKey(ch)
    local item = theList:getSelectedItem()

    -- TODO: move a lot of these into list:handleKey
    if ckBinding(bubble, bindings.ADD) then
        local taskMsg = promptStr("Add task")
        local res = execTask("add", '"'..string.gsub(taskMsg, '"', '\\"')..'"')
        theList.items = reread()
        feedback("Added task: "..taskMsg, res)
        needRefresh = true
    elseif ckBinding(bubble, bindings.DELETE) then
        if promptStr("Really delete task '"..item.description.."'?")=="yes" then
            local res = execTask(item.uuid, "delete")
            feedback("Deleted task '"..item.description.."'.", res)
            theList.items = reread()
            needRefresh = true
        end
    elseif ckBinding(bubble, bindings.DONE) then
        local res = execTask(item.uuid, "done")
        feedback("'"..item.description .. "' done!", res)
        theList.items = reread()
        needRefresh = true
    elseif ckBinding(bubble, bindings.EDIT) then
        local newDesc = promptStr("Enter new description", item.description)
        if newDesc then
            local res = execTask(item.uuid, "modify", newDesc)
            feedback("Updated '"..item.description.."' to '"..newDesc.."'.", res)
            theList.items = reread()
            needRefresh = true
        end
    elseif ckBinding(bubble, bindings.PROCRASTINATE) then
        local procrast = promptStr("Procrastinate by", "1day")
        if procrast then
            local res = execTask(item.uuid, "modify", "wait:"..procrast)
            feedback("Procrastinated task '"..item.description.."' by "..procrast..".", res)
            theList.items = reread()
            needRefresh = true
        end
    elseif  ckBinding(bubble, bindings.DUE) then
        local due = promptStr("Set task due date")
        if due then
            local res = execTask(item.uuid, "modify", "due:"..due)
            feedback(res)
            theList.items = reread()
            needRefresh = true
        end
    elseif ckBinding(bubble, bindings.FOLLOW)  then
        local letterMap = {}
    
        curses.attrset(curses.color_pair(COLOR_SELECTION))
        for k,ft in pairs(followTargets) do
            if k > #ftLetters then break end
            local ft = followTargets[k]
            local letter = ftLetters:sub(k, k)
            letterMap[letter] = ft
            stdscr:mvaddstr(ft.y, ft.x, " "..letter.." ")
        end
        curses.attrset(0)
        stdscr:refresh()
        local ft = letterMap[getKey()]
        if ft then ft.cb() end
        needRefresh = true
    elseif ckBinding(bubble, bindings.REREAD)  then
        theList.items = reread()
        feedback("Reloaded task list.")
        needRefresh = true
    end

end

if c and c < 256 then c = string.char(c) end
curses.endwin()
if c == 'y' then
    local a = {};  for k in pairs(curses) do a[#a+1]=k end
    table.sort(a)
    for i,k in ipairs(a) do print(type(curses[k])..'  '..k) end
end

dump(curses.color_pair(1))

reread()

print(dump(tasks))
