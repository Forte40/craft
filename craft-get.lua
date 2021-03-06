--http://pastebin.com/XCyjKvzP

local branch = "master"
if fs.exists(".craft.branch") then
  local f = fs.open(".craft.branch", "r")
  branch = f.readAll()
  f.close()
end  

local files = {
  {
    name = "craft-get",
    url = "https://raw.github.com/Forte40/craft/"..branch.."/craft-get.lua"
  },
  {
    name = "craft",
    url = "https://raw.github.com/Forte40/craft/"..branch.."/craft.lua"
  },
  {
    name = "panel",
    folder = "apis",
    url = "https://raw.github.com/Forte40/panel/master/panel.lua"
  },
}

local scripts = {"Unleashed_1.1.3"}

local cmd = ...
if cmd == "list" then
  textutils.pagedPrint(table.concat(scripts, "\n"))
  return
elseif cmd then
  local found = false
  for _, name in ipairs(scripts) do
    if cmd == name then
      found = true
      break
    end
  end
  if found then
    files = {
      {
        name = "item.dat",
        url = "https://raw.github.com/Forte40/craft/"..branch.."/"..cmd.."/item.dat"
      },
      {
        name = "dictionary.dat",
        url = "https://raw.github.com/Forte40/craft/"..branch.."/"..cmd.."/dictionary.dat"
      },
      {
        name = "recipe.dat",
        url = "https://raw.github.com/Forte40/craft/"..branch.."/"..cmd.."/recipe.dat"
      },
    }
  else
    print("script '"..cmd.."' does not exists")
    return
  end
end

if not http then
  print("No access to web")
  return
end

for _, file in ipairs(files) do
  local path
  if file.folder then
    if not fs.exists(file.folder) then
      fs.makeDir(file.folder)
    end
    path = fs.combine(file.folder, file.name)
  else
    path = file.name
  end
  local currText = ""
  if fs.exists(path) then
    local f = fs.open(path, "r")
    currText = f.readAll()
    f.close()
    io.write("update  ")
  else
    io.write("install ")
  end
  io.write("'"..file.name.."'"..string.rep(" ", math.max(0, 8 - #file.name)))
  if file.folder then
    io.write(" in '"..file.folder.."'"..string.rep(".", math.max(0, 8 - #file.folder)).."...")
  else
    io.write("    .............")
  end
  local request = http.get(file.url)
  if request then
    local response = request.getResponseCode()
    if response == 200 then
      local newText = request.readAll()
      if newText == currText then
        print("skip")
      else
        local f = fs.open(path, "w")
        f.write(newText)
        f.close()
        print("done")
      end
    else
      print(" bad HTTP response code " .. response)
    end
  else
    print(" no request handle")
  end
  os.sleep(0.1)
end
