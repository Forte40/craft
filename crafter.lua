--[[ TODO
add yield to recipe
add generic materials aka forge
add making multiples for speed
add multiple direction logic
add ui
]]
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

local s, w, dir
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
  if fs.exists(".crafter.direction") then
    local f = fs.open(".crafter.direction", "r")
    local d = tonumber(f.readAll())
    f.close()
    dir = d
  else
    print("Initializing Crafter")
    print("  please empty the system and")
    print("  put items in the turtle")
    print("  then hit enter")
    io.read()
    for i = 0, 5 do
      local l = s.list(i)
      if l then
        tprint(l)
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
function addString(s, id)
  s = s:lower()
  for i = 1, #s do
    addTrie(s:sub(i), id, gtrie)
  end
  table.insert(gtrie, id)
end

function addTrie(s, id, trie)
  if s == "" then
    return
  end
  local c = s:sub(1,1)
  if trie[c] then
    local found = false
    for _, existingID in ipairs(trie[c]) do
      if existingID == id then
        found = true
        break
      end
    end
    if not found then
      table.insert(trie[c], id)
    end
  else
    trie[c] = {id}
  end
  addTrie(s:sub(2), id, trie[c])
end

io.write("loading ids...")
local count = 0
local ids = {}
local names = {[""] = 0}
for _, idfile in ipairs(fs.list("ids")) do
  idfile = fs.combine("ids", idfile)
  if not fs.isDir(idfile) then
    local f = fs.open(idfile, "r")
    local data = f.readAll()
    f.close()
    ids = textutils.unserialize(data)
    for id, name in pairs(ids) do
      count = count + 1
      addString(name, id)
      names[name] = id
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
    print(textutils.serialize(recipes))
  end
end
print(count)

local inv = {}

function idAdd(id, amount, direction)
  if inv[id] then
    if inv[id].amount[direction] then
      inv[id].amount[direction] = inv[id].amount[direction] + amount
    else
      inv[id].amount[direction] = amount
    end
    inv[id].total = inv[id].total + amount
  else
    inv[id] = {id=id%32768, meta=math.floor(id/32786),amount={[direction]=amount},total=amount}
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
  print("requesting "..amount.." "..ids[id].." in "..textutils.serialize(slots))
  local total = amount * #slots
  print(total)
  if not inv[id] then
    print("do not have "..ids[id])
  elseif inv[id].total < total then
    print("need more "..ids[id])
  else
    turtle.select(1)
    for i, slot in ipairs(slots) do
      print("slot", slot)
      tprint(inv[id].amount)
      for direction, count in pairs(inv[id].amount) do
        if count >= amount then
          print("extracting")
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
  print("making "..tostring(amount).." "..ids[id])
  local r = recipes[id]
  tprint(r)
  if not r then
    print("can't make "..ids[id]..", no recipe")
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
        print("can't make "..ids[id]..", need "..needed.." "..ids[mid])
        return false
      end
    end
  end
  while amount > 0 do
    local currAmount = amount > 64 and 64 or amount
    amount = amount - 64
    for mid, slots in pairs(mat) do
      request(mid, amount, slots)
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
local name = ...
if name then
  for _, id in ipairs(search(name:lower())) do
    local count = inv[id] or 0
    print(ids[id].." = "..count)
  end
end
--make(54, 8)

local text = ""

function sortTotal(a, b)
  if inv[a] then
    if inv[b] then
      return inv[a].total > inv[b].total
    else
      return true
    end
  elseif inv[b] then
    return false
  else
    return true
  end
end

os.loadAPI("panel")
local panelItems = panel.new{y=2, h=10}
local panelSearch = panel.new{y=12, h=1}

function listItems(text)
  local sids = search(text)
  table.sort(sids, sortTotal)
  panelItems:redirect()
  local width, height = term.getSize()
  term.clear()
  for i = 1, math.min(sids and #sids or height, height - 1) do
    local id = sids[i]
    term.setCursorPos(1, i)
    write(tostring(inv[id] and inv[id].total or 0))
    write(" ")
    write(ids[id])
  end
end

term.clear()
listItems("")
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
    end
  end
end