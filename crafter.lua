--[[ TODO
add yield to recipe
add generic materials aka forge
add making multiples for speed
add multiple direction logic
add ui
]]

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

local s, w, dir, capacity

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
    dir = d
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
          dir = i
          break
        end
      end
    end
  end
  for i = 0, 5 do
    if i ~= dir then
      local l = s.list(i)
      if l then
        table.insert(chests, i)
      end
    end
  end
end

local gtrie = {}
local names = {[""] = 0}
function addString(s, id)
  names[s] = id
  s = s:lower()
  for i = 1, #s do
    addTrie(s:sub(i), id, gtrie)
  end
  gtrie[id] = true
end

function addTrie(s, id, trie)
  if s == "" then
    return
  end
  local c = s:sub(1,1)
  if trie[c] then
    trie[id] = true
  else
    trie[c] = {id}
  end
  addTrie(s:sub(2), id, trie[c])
end

function getMeta(uuid)
  if type(uuid) == "number" then
    return uuid%32768, math.floor(uuid/32768)
  elseif type(uuid) == "string" then
    local pos = uuid:find(":")
    local uuidmeta = tonumber(uuid:sub(pos+1))
    uuid = tonumber(uuid:sub(1, pos-1))
    print(uuid, uuidmeta)
    return uuid, uuidmeta
  end
end

function getId(id, meta)
  return meta * 32768 + id
end

io.write("loading ids...")
local count = 0
local ids = {}
for _, idfile in ipairs(fs.list("ids")) do
  idfile = fs.combine("ids", idfile)
  if not fs.isDir(idfile) then
    local f = fs.open(idfile, "r")
    local data = f.readAll()
    f.close()
    local lids = textutils.unserialize(data)
    for uuid, name in pairs(lids) do
      local id, meta = getMeta(uuid)
      uuid, uuidmeta = getId(id, meta)
      local stackSize = 64
      if type(name) == "table" then
        name, stackSize = unpack(name)
      end
      ids[uuid] = {name=name, stackSize=stackSize}
      count = count + 1
      addString(name, uuid)
      addString(tonumber(id)..":"..tonumber(meta), uuid)
    end
  end
end
print(count)

io.write("loading recipes...")
local count = 0
local recipes = {}
for _, recipefile in ipairs(fs.list("recipe")) do
  recipefile = fs.combine("recipe", recipefile)
  if not fs.isDir(recipefile) then
    local f = fs.open(recipefile, "r")
    local data = f.readAll()
    f.close()
    local rs = textutils.unserialize(data)
    for name, items in pairs(rs) do
      count = count + 1
      if not names[name] then
        error("unknown item name "..name.." in recipe "..name)
      else
        local r = {yield = table.remove(items, 1)}
        recipes[names[name]] = r
        for i, item in ipairs(items) do
          if not names[item] then
            error("unknown item name "..item.." in recipe "..name)
          else
            table.insert(r, names[item])
          end
        end
      end
    end
  end
end
print(count)

local inv = {}

function idAdd(uuid, amount, direction)
  if ids[uuid] == nil then
    local id, meta = getMeta(uuid)
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
  if not inv[id] then
    return amount
  elseif inv[id].total < amount then
    return amount - inv[id].total
  else
    return 0
  end
end

function request(id, amount, slots)
  --print("requesting "..amount.." "..ids[id].name.." in "..textutils.serialize(slots))
  local total = amount * #slots
  print(total)
  if not inv[id] then
    print("do not have "..ids[id].name)
  elseif inv[id].total < total then
    print("need more "..ids[id].name)
  else
    turtle.select(1)
    for i, slot in ipairs(slots) do
      --print("slot", slot)
      --tprint(inv[id].amount)
      for direction, count in pairs(inv[id].amount) do
        if count >= amount then
          --print("extracting")
          s.extract(direction, id, dir, amount)
          idSub(id, amount, direction)
          turtle.transferTo(craftSlot[slot])
          break
        end
      end
    end
  end
end

function getDirection(id)
  if inv[id] then
    for direction, count in pairs(inv[id].amount) do
      if count > 0 then
        return direction
      end
    end
  end
  for _, direction in ipairs(chests) do
    if direction ~= dir then
      return direction
    end
  end
end

function make(id, amount)
  amount = amount or 1
  print("making "..tostring(amount).." "..ids[id].name)
  local r = recipes[id]
  --tprint(r)
  if not r then
    print("can't make "..ids[id].name..", no recipe")
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
      if not make(mid, needed) then
        print("can't make "..ids[id].name..", need "..needed.." "..ids[mid].name)
        return false
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
    local direction = getDirection(id)
    s.extract(dir, id, direction, count)
    idAdd(id, count, direction)
  end
  return true
end

function unloadTurtle()
  local items = s.list(dir)
  for id, amount in pairs(items) do
    if inv[id] and inv[id].direction then
      s.extract(dir, id, inv[id].direction, amount)
    else
      for _, direction in ipairs(chests) do
        if s.extract(dir, id, direction, amount) then
          break
        end
      end
    end
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
  for id in pairs(list) do
    if type(id) == "number" and (
        display == 1 or
        (display == 3 or display == 4 and recipes[id] ~= nil) or
        (display == 2 or display == 4 and inv[id] ~= nil and inv[id].total > 0)
        ) then
      table.insert(fids, id)
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

os.loadAPI("panel")

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

local status = {
 display = 4,
 displayText = {" all  ", "stored", "craft ", " both "},
 order = 1,
 orderText = {"count", "name ", " id  ", "stack"},
 orderDir = 1,
 orderDirText = {"desc", "asc "},
 selected = 1,
 page = 1,
 pages = 1,
 pageSize = term.getSize(),
 searchTotal = 0,
 focus = true,
 idSelected = 1
}

function changeId(up)
  panelItems:redirect()
  term.setCursorPos(5, status.idSelected)
  term.write(" ")
  status.idSelected = rotate(status.idSelected, math.min(status.pageSize, status.searchTotal), up)
  term.setCursorPos(5, status.idSelected)
  term.write(">")
end

function listItems(text)
  panelItems:redirect()
  local sids = search(text:lower())
  if sids then
    status.idSelected = 1
    sids = filterBy(sids, status.display)
    status.ids = sids
    status.searchTotal = #sids
    if status.order == 1 then
      table.sort(sids, orderBy(inv, "total", status.orderDir == 1))
    elseif status.order == 2 then
      table.sort(sids, orderBy(ids, "name", status.orderDir == 1))
    elseif status.order == 3 then
      table.sort(sids)
    elseif status.order == 4 then
      table.sort(sids, orderBy(ids, "stackSize", status.orderDir == 1))
    end
    local width, height = term.getSize()
    term.clear()
    for i = 1, math.min(sids and #sids or height, height) do
      local id = sids[i]
      term.setCursorPos(1, i)
      write(formatNumber(inv[id] and inv[id].total or 0))
      if not status.focus and status.idSelected == i then
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
  write("status")
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
  write(" page")
  write(formatNumber(status.page))
  write(" of ")
  write(formatNumber(status.pages))
end

function main()
  showStatus()
  local text = ""
  panelItems:redirect()
  term.clear()
  listItems("")
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
      listItems(text)
    elseif event == "key" then
      if code == keys.backspace then
        term.setCursorPos(#text, 1)
        write(" ")
        term.setCursorPos(#text, 1)
        text = text:sub(1, #text - 1)
        listItems(text)
      elseif code == keys.delete then
        term.setCursorPos(1, 1)
        write(string.rep(" ", width))
        term.setCursorPos(1, 1)
        text = ""
        listItems(text)
      elseif code == keys.f5 then
        unloadTurtle()
        getInventory()
        listItems(text)
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
          listItems(text)
        else
          changeId(true)
        end
      elseif code == keys.down then
        if status.focus then
          changeOption(false)
          listItems(text)
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