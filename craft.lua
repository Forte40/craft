--[[ TODO
add yield to recipe
add generic materials aka forge
add making multiples for speed
add multiple direction logic
add ui
]]

function serialize(o, indent)
  local s = ""
  indent = indent or ""
  if type(o) == "number" then
    s = s .. indent .. tostring(o)
  elseif type(o) == "boolean" then
    s = s .. indent .. (o and "true" or "false")
  elseif type(o) == "string" then
    if o:find("\n") then
      s = s .. indent .. "[[\n" .. o:gsub("\"", "\\\"") .. "]]"
    else
      s = s .. indent .. string.format("%q", o)
    end
  elseif type(o) == "table" then
    s = s .. "{\n"
    for k,v in pairs(o) do
      if type(v) == "table" then
        s = s .. indent .. "  [" .. serialize(k) .. "] = " .. serialize(v, indent .. "  ") .. ",\n"
      else
        s = s .. indent .. "  [" .. serialize(k) .. "] = " .. serialize(v) .. ",\n"
      end
    end
    s = s .. indent .. "}"
  else
    s = s .. indent .. "nil"
    --error("cannot serialize a " .. type(o))
  end
  return s
end

local chestCapacity = {
  chest = 27,
  copper_chest = 45,
  iron_chest = 54,
  silver_chest = 72,
  gold_chest = 81,
  diamond_chest = 108,
  ender_chest = 27
}

function tprint (tbl, indent, max)
  if not max then max = 12 end
  if not indent then indent = 0 end
  if indent >= max then return end
  if tbl == nil then
    print("nil")
  elseif type(tbl) == "string" then
    print(tbl)
  else
    for k, v in pairs(tbl) do
      formatting = string.rep("  ", indent) .. k .. ": "
      if type(v) == "table" then
        print(formatting)
        tprint(v, indent+1, max)
      elseif type(v) == "boolean" then
        print(formatting .. tostring(v))
      else
        print(formatting .. v)
      end
    end
  end
end

local s, w, turtleDirection, capacity

local chests = {}
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "interactiveSorter" then
    s = peripheral.wrap(side)
  elseif peripheral.getType(side) == "workbench" then
    w = side
  end
end
if not w then
  print("Program needs a crafty turtle")
end
if not s then
  print("Program needs an interactive sorter")
  return
end

function initialize()
  if fs.exists(".crafter.capacity") then
    local f = fs.open(".crafter.capacity", "r")
    local d = textutils.unserialize(f.readAll())
    f.close()
    capacity = d
  else
    print("Assuming single wooden chests")
    print("  edit .crafter.capacity to upgrade chest sizes")
    print()
    print("press [Enter] to continue...")
    capacity = {[0]=27, [1]=27, [2]=27, [3]=27, [4]=27, [5]=27}
    local f = fs.open(".crafter.capacity", "w")
    f.write(textutils.serialize(capacity))
    f.close()
    read()
  end
  if fs.exists(".crafter.direction") then
    local f = fs.open(".crafter.direction", "r")
    local d = tonumber(f.readAll())
    f.close()
    turtleDirection = d
  else
    print("Initializing Crafter")
    print("  please empty the system and")
    print("  put items in the turtle")
    print("  then press [Enter] to continue...")
    io.read()
    for i = 0, 5 do
      local l = s.list(i)
      if l then
        --tprint(l)
        if not (next(l) == nil) then
          local f = fs.open(".crafter.direction", "w")
          f.write(i)
          f.close()
          turtleDirection = i
          break
        end
      end
    end
  end
  for i = 0, 5 do
    if i ~= turtleDirection then
      local l = s.list(i)
      if l then
        table.insert(chests, i)
      end
    end
  end
end

local gtrie = {}
local names = {[""] = 0}
function addString(s, uuid)
  names[s] = uuid
  s = s:lower()
  for i = 1, #s do
    addTrie(s:sub(i), uuid, gtrie)
  end
  gtrie[uuid] = true
  return s
end

function addTrie(s, uuid, trie)
  if s == "" then
    return
  end
  local c = s:sub(1,1)
  if trie[c] then
    trie[c][uuid] = true
  else
    trie[c] = {[uuid]=true}
  end
  addTrie(s:sub(2), uuid, trie[c])
end

function getIdMeta(uuid)
  if type(uuid) == "number" then
    return uuid%32768, math.floor(uuid/32768)
  elseif type(uuid) == "string" then
    local pos = uuid:find(":")
    if pos then
      local uuidmeta = tonumber(uuid:sub(pos+1))
      uuid = tonumber(uuid:sub(1, pos-1))
      return uuid, uuidmeta
    else
      return nil
    end
  end
end

function getUuid(id, meta)
  return meta * 32768 + id
end

io.write("loading items...")
local count = 0
local ids = {}
local f = fs.open("item.dat", "r")
local data = f.readAll()
f.close()
local lids = textutils.unserialize(data)
for uuid, name in pairs(lids) do
  count = count + 1
  -- pause execution to prevent "Too long without yielding"
  if count % 1000 == 0 then
    os.queueEvent("crafter")
    os.pullEvent("crafter")
  end
  local id, meta = getIdMeta(uuid)
  uuid = getUuid(id, meta)
  -- add list of sub items to item with meta = 0
  if meta > 0 and ids[id] then
    if ids[id].subUuids then
      table.insert(ids[id].subUuids, uuid)
    else
      ids[id].subUuids = {id, uuid}
    end
  end
  local stackSize = 64
  if type(name) == "table" then
    name, stackSize = unpack(name)
  else
    if name:find("urnace") then
      print(tonumber(id)..":"..tonumber(meta))
      print(name)
      read()
    end
  end
  addString(name, uuid)
  addString(tonumber(id)..":"..tonumber(meta), uuid)
  ids[uuid] = {name=name, stackSize=stackSize}
end
print(count)

io.write("loading dictionary...")
local count = 0
local dictionary = {}
local f = fs.open("dictionary.dat", "r")
local data = f.readAll()
f.close()
local ores = textutils.unserialize(data)
for name, uuids in pairs(ores) do
  count = count + 1
  dictionary[name] = {}
  for _, uuid in ipairs(uuids) do
    local id, meta = getIdMeta(uuid)
    if meta == 32767 then
      -- all meta ids apply to this ore
      if ids[id] and ids[id].subUuids then
        for _, subUuid in ipairs(ids[id].subUuids) do
          table.insert(dictionary[name], subUuid)
        end
      else
        table.insert(dictionary[name], id)
      end
    else
      uuid = getUuid(id, meta)
      table.insert(dictionary[name], uuid)
    end
  end
end
print(count)

io.write("loading recipes...")
local count = 0
local recipes = {}
local f = fs.open("recipe.dat", "r")
local data = f.readAll()
f.close()
local craftings = textutils.unserialize(data)
for outputUuid, inputUuids in pairs(craftings) do
  count = count + 1
  -- pause execution to prevent "Too long without yielding"
  if count % 1000 == 0 then
    os.queueEvent("crafter")
    os.pullEvent("crafter")
  end
  local recipe = {yield = table.remove(inputUuids, 1)}
  local id, meta = getIdMeta(outputUuid)
  outputUuid = getUuid(id, meta)
  recipes[outputUuid] = recipe
  for _, inputUuid in ipairs(inputUuids) do
    if inputUuid and inputUuid ~= "" then
      id, meta = getIdMeta(inputUuid)
      if id then
        if meta == 32767 then
          local idEntry = ids[id]
          if idEntry and idEntry.subUuids then
            -- add dictionary entries
            dictionary[idEntry.name] = {}
            for _, subUuid in ipairs(idEntry.subUuids) do
              table.insert(dictionary[idEntry.name], subUuid)
            end
            table.insert(recipe, idEntry.name)
          else
            table.insert(recipe, id)
          end
        else
          local uuid = getUuid(id, meta)
          table.insert(recipe, uuid)
        end
      else
        -- ore dictionary entry
        table.insert(recipe, inputUuid)
      end
    else
      table.insert(recipe, 0)
    end
  end
end
print(count)

local inv = {}

function idPutBest(uuid, amount)
  if inv[uuid] then
    local bestDir, highAmount = 0, 0
    for direction, amount in pairs(inv[uuid].amount) do
      if amount > highAmount then
        bestDir = direction
        highAmount = amount
      end
    end
    idPut(uuid, amount, bestDir)
  else
    for _, direction in ipairs(chests) do
      idPut(uuid, amount, direction)
    end
  end
end

function idPut(uuid, amount, direction)
  s.extract(turtleDirection, uuid, direction, amount)
  idAdd(uuid, amount, direction)
end

function idAdd(uuid, amount, direction)
  if direction == turtleDirection then
    return
  end
  if ids[uuid] == nil then
    local id, meta = getIdMeta(uuid)
    local name = tostring(id)..":"..tostring(meta)
    ids[uuid] = {name=name, stackSize=64}
    addString(name, uuid)
  end
  if inv[uuid] then
    if inv[uuid].amount[direction] then
      inv[uuid].amount[direction] = inv[uuid].amount[direction] + amount
    else
      inv[uuid].amount[direction] = amount
    end
    inv[uuid].total = inv[uuid].total + amount
  else
    inv[uuid] = {id=uuid%32768, meta=math.floor(uuid/32768),amount={[direction]=amount},total=amount}
  end
end

function idGet(uuid, amount, direction)
  s.extract(direction, uuid, turtleDirection, amount)
  idSub(uuid, amount, direction)
end

function idSub(id, amount, direction)
  if inv[id] then
    inv[id].amount[direction] = inv[id].amount[direction] - amount
    if inv[id].amount[direction] <= 0 then
      inv[id].amount[direction] = nil
    end
    inv[id].total = inv[id].total - amount
    if inv[id].total <= 0 then
      inv[id] = nil
    end
  end
end

function getInventory()
  inv = {}
  for direction = 0, 5 do
    local l = s.list(direction)
    if l then
      for id, count in pairs(l) do
        idAdd(id, count, direction)
      end
    end
  end
end

local craftSlot = {[1] = 5,
                   [2] = 6,
                   [3] = 7,
                   [4] = 9,
                   [5] = 10,
                   [6] = 11,
                   [7] = 13,
                   [8] = 14,
                   [9] = 15}

function verify(id, amount)
  local needed = amount
  local vids
  if type(id) == "string" then
    vids = dictionary[id]
  else
    vids = {id}
  end
  if vids then
    for _, vid in ipairs(vids) do
      if inv[vid] then
        needed = needed - inv[vid].total
      end
    end
  end
  return math.max(0, needed)
end

function request(id, amount, slots)
  --[[
  if type(id) == "string" then
    print("requesting "..amount.." "..id.." in "..textutils.serialize(slots))
  else
    print("requesting "..amount.." "..ids[id].name.." in "..textutils.serialize(slots))
  end
  ]]
  local total = amount * #slots
  local needed = verify(id, total)
  if needed > 0 then
    if type(id) == "string" then
      print("need more "..id)
    else
      print("need more "..ids[id].name)
    end
    return false
  else
    turtle.select(1)
    -- fill 1 slot at a time
    for i, slot in ipairs(slots) do
      if type(id) == "string" then
        local ores = dictionary[id]
        for _, ore in ipairs(ores) do
          if verify(ore, amount) <= 0 then
            if request(ore, amount, {slot}) then
              break
            end
          end
        end
      else
        for direction, count in pairs(inv[id].amount) do
          if count >= amount then
            idGet(id, amount, direction)
            turtle.transferTo(craftSlot[slot])
            break
          end
        end
      end
    end
    return true
  end
end

function make(uuid, amount, makeStack)
  makeStack = makeStack or {}
  makeStack[uuid] = true
  amount = amount or 1
  if not ids[uuid] then
    return false
  end
  print("making "..tostring(amount).." "..ids[uuid].name)
  local r = recipes[uuid]
  if not r then
    print("can't make "..ids[uuid].name..", no recipe")
    return false
  end
  amount = math.ceil(amount / r.yield)
  local mat = {}
  for loc, mid in ipairs(r) do
    if mid ~= 0 then
      if mat[mid] then
        table.insert(mat[mid], loc)
      else
        mat[mid] = {loc}
      end
    end
  end
  for mid, slots in pairs(mat) do
    local needed = verify(mid, amount * #slots)
    if needed > 0 then
      if type(mid) == "string" then
        print("making "..needed.." "..mid)
        local made = false
        local ores = dictionary[mid]
        for _, ore in ipairs(ores) do
          if not makeStack[ore] and make(ore, needed, makeStack) then
            made = true
            break
          end
        end
        if not made then
          print("can't make "..ids[uuid].name..", need "..needed.." "..mid)
          return false
        end
      else
        if makeStack[mid] or not make(mid, needed, makeStack) then
          if ids[mid] then
            print("can't make "..ids[uuid].name..", need "..needed.." "..ids[mid].name)
          else
            print("can't make "..ids[uuid].name..", need "..needed.." "..tostring(mid))
          end
          return false
        end
      end
    end
  end
  while amount > 0 do
    local currAmount = amount > 64 and 64 or amount
    amount = amount - 64
    for mid, slots in pairs(mat) do
      request(mid, currAmount, slots)
    end
    turtle.select(1)
    turtle.craft()
    local count = turtle.getItemCount(1)
    idPutBest(uuid, count)
  end
  return true
end

function unloadTurtle()
  local items = s.list(turtleDirection)
  for uuid, amount in pairs(items) do
    idPutBest(uuid, amount)
  end
end

function search(name, trie)
  trie = trie or gtrie
  if name == "" then
    return trie
  end
  c = name:sub(1,1)
  if trie[c] then
    return search(name:sub(2), trie[c])
  end
end

--tprint(gtrie)
initialize()
getInventory()
unloadTurtle()

function orderBy(lookup, prop, descending, default)
  lookup = lookup or inv
  if descending == nil then descending = false end
  if default == nil then default = 0 end
  return function (a, b)
    local av, bv
    if prop then
      av = lookup[a] and lookup[a][prop] or default
      bv = lookup[b] and lookup[b][prop] or default
    else
      av = lookup[a] or default
      bv = lookup[b] or default
    end
    return (av > bv) == descending
  end
end

function filterBy(list, display)
  local fids = {}
  for uuid in pairs(list) do
    if type(uuid) == "number" and (
        display == 1 or
        ((display == 3 or display == 4) and recipes[uuid] ~= nil) or
        ((display == 2 or display == 4) and inv[uuid] ~= nil and inv[uuid].total > 0)
        ) then
      table.insert(fids, uuid)
    end
  end
  return fids
end

function formatNumber(n)
  if n < 10 then
    return "   "..tostring(n)
  elseif n < 100 then
    return "  "..tostring(n)
  elseif n < 1000 then
    return " "..tostring(n)
  elseif n < 10000 then
    return tostring(n)
  elseif n < 100000 then
    return " "..tostring(math.floor(n / 1000)).."K"
  elseif n < 1000000 then
    return tostring(math.floor(n / 1000)).."K"
  else
    return tostring(math.floor(n / 100000) / 10).."M"
  end
end

os.loadAPI("apis/panel")

local panelSearch = panel.new{y=-1, h=-1}
panelSearch:redirect()
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()

local panelStatus = panel.new{y=1, h=1}
panelStatus:redirect()
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()

local panelItems = panel.new{y=2, h=-3}
panelItems:redirect()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
local width, height = term.getSize()

local status = {
 display = 4,
 displayText = {" all  ", "stored", "craft ", " both "},
 order = 1,
 orderText = {"count", "name ", " id  ", "stack"},
 orderDir = 1,
 orderDirText = {"desc", "asc "},
 selected = 1,
 focus = false,
 searchTotal = 0,
 idViewed = 1,
 idSelected = 1,
 pageSize = height,
}

function changeId(up)
  panelItems:redirect()
  term.setCursorPos(5, status.idSelected - status.idViewed + 1)
  term.write(" ")
  if status.idSelected > 1 and up then
    status.idSelected = status.idSelected - 1
  elseif status.idSelected < status.searchTotal and not up then
    status.idSelected = status.idSelected + 1
  end
  if status.idSelected < status.idViewed then
    status.idViewed = status.idSelected
    listItems()
  elseif status.idSelected > (status.idViewed + status.pageSize - 1) then
    status.idViewed = math.min(status.searchTotal - status.pageSize + 1, status.idSelected)
    listItems()
  end
  term.setCursorPos(5, status.idSelected - status.idViewed + 1)
  term.write(">")
  showStatus()
end

function searchItems(text)
  local sids = search(text:lower())
  if sids then
    status.idSelected = 1
    status.idViewed = 1
    sids = filterBy(sids, status.display)
    if status.order == 1 then
      table.sort(sids, orderBy(inv, "total", status.orderDir == 1))
    elseif status.order == 2 then
      table.sort(sids, orderBy(ids, "name", status.orderDir == 1))
    elseif status.order == 3 then
      table.sort(sids)
    elseif status.order == 4 then
      table.sort(sids, orderBy(ids, "stackSize", status.orderDir == 1))
    end
    status.ids = sids
    status.searchTotal = #sids
  else
    status.ids = nil
  end
  listItems()
  showStatus()
end

function listItems()
  panelItems:redirect()
  if status.ids then
    local width, height = term.getSize()
    term.clear()
    for i = status.idViewed, status.idViewed + math.min(#status.ids, status.pageSize) - 1 do
      local id = status.ids[i]
      term.setCursorPos(1, i - status.idViewed + 1)
      write(formatNumber(inv[id] and inv[id].total or 0))
      if status.idSelected == i then
        write(">")
      else
        write(" ")
      end
      write(ids[id].name)
    end
  else
    term.clear()
    status.searchTotal = 0
    status.idSelected = 0
  end
end

function rotate(n, max, decrement)
  if decrement then
    n = n - 1
    if n < 1 then n = max end
  else
    n = n + 1
    if n > max then n = 1 end
  end
  return n
end

function changeSelected(forward)
  status.selected = rotate(status.selected, 3, forward)
  showStatus()
end

function changeOption(up)
  if status.selected == 1 then
    status.display = rotate(status.display, #status.displayText, up)
  elseif status.selected == 2 then
    status.order = rotate(status.order, #status.orderText, up)
  elseif status.selected == 3 then
    status.orderDir = rotate(status.orderDir, #status.orderDirText, up)
  end
  showStatus()
end

function showStatus()
  panelStatus:redirect()
  term.setCursorPos(1, 1)
  for i = 1, 3 do
    if status.focus and status.selected == i then
      --term.setTextColor(colors.white)
      write("<")
    else
      --term.setTextColor(colors.black)
      write(" ")
    end
    if i == 1 then
      write(status.displayText[status.display])
    elseif i == 2 then
      write(status.orderText[status.order])
    elseif i == 3 then
      write(status.orderDirText[status.orderDir])
    end
    if status.focus and status.selected == i then
      write(">")
    else
      write(" ")
    end
  end
  term.setTextColor(colors.black)
  write(" item")
  write(formatNumber(status.idSelected))
  write(" of ")
  write(formatNumber(status.searchTotal))
end

function main()
  showStatus()
  local text = ""
  panelItems:redirect()
  term.clear()
  searchItems("")
  term.setCursorBlink(true)
  term.setCursorPos(1, 1)
  while true do
    panelSearch:redirect()
    local width = term.getSize()
    local event, code = os.pullEvent()
    if event == "char" then
      text = text .. code
      term.setCursorPos(#text, 1)
      write(code)
      searchItems(text)
    elseif event == "key" then
      if code == keys.backspace then
        term.setCursorPos(#text, 1)
        write(" ")
        term.setCursorPos(#text, 1)
        text = text:sub(1, #text - 1)
        searchItems(text)
      elseif code == keys.delete then
        term.setCursorPos(1, 1)
        write(string.rep(" ", width))
        term.setCursorPos(1, 1)
        text = ""
        searchItems(text)
      elseif code == keys.f5 then
        unloadTurtle()
        getInventory()
        searchItems(text)
      elseif code == keys.left then
        if status.focus then
          changeSelected(true)
        end
      elseif code == keys.right then
        if status.focus then
          changeSelected(false)
        end
      elseif code == keys.up then
        if status.focus then
          changeOption(true)
          searchItems(text)
        else
          changeId(true)
        end
      elseif code == keys.down then
        if status.focus then
          changeOption(false)
          searchItems(text)
        else
          changeId(false)
        end
      elseif code == keys.tab then
        status.focus = not status.focus
        showStatus()
      elseif code == keys.pageUp then
      elseif code == keys.pageDown then
      elseif code == keys.enter then
        local id = status.ids[status.idSelected]
        local count = 64
        if inv[id] == nil or inv[id].total == nil or inv[id].total < 0 then
          panelSearch:redirect()
          term.clear()
          write("How many? ")
          count = tonumber(read())
          count = count or 1
          if count then
            panelItems:redirect()
            term.clear()
            if not make(id, count) then
              print("press [Enter] to continue...")
              read()
            end
          end
          panelSearch:redirect()
          term.clear()
          write(text)
        end
        if inv[id] ~= nil and inv[id].total > 0 then
          request(id, math.min(count, inv[id].total), {7})
        end
        listItems(text)
      end
    end
  end
  term.restore()
  term.clear()
end

main()