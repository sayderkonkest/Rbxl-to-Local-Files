local allServices = {
    "Workspace",
    "Lighting",
    "MaterialService",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "Teams",
    "SoundService",
    "TextChatService"
}

local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local roblox = require("@lune/roblox")

local function create(child: Instance, dir: string)
    local newDir = `{dir}/{child.Name}`
    local hasSubChild = #child:GetChildren() > 0

    if child:IsA("Folder") then
        fs.writeDir(newDir)

        if hasSubChild then
            for _, subChild in child:GetChildren() do
                create(subChild, newDir)
            end
        end
    elseif child:IsA("StarterCharacterScripts") or child:IsA("StarterPlayerScripts") then
        fs.writeDir(newDir)

        if hasSubChild then
            for _, subChild in child:GetChildren() do
                create(subChild, newDir)
            end
        end
    elseif child:IsA("ModuleScript") then
        fs.writeDir(newDir)
        fs.writeFile(`{newDir}/init.luau`, child.Source)

        if hasSubChild then
            for _, subChild in child:GetChildren() do
                create(subChild, newDir)
            end
        end
    elseif child.ClassName == "Script" then
        local runContext = child.RunContext.Name

        if runContext == "Client" then
            fs.writeFile(`{newDir}.client.luau`, child.Source)
            
            if hasSubChild then
                for _, subChild in child:GetChildren() do
                    create(subChild, newDir)
                end
            end
        elseif runContext == "Server" or runContext == "Legacy" or runContext == "Plugin" then
            if hasSubChild then
                fs.writeDir(newDir)
                fs.writeFile(`{newDir}/init.server.luau`, child.Source)

                for _, subChild in child:GetChildren() do
                    create(subChild, newDir)
                end
            else
                fs.writeFile(`{newDir}.server.luau`, child.Source)
            end
        end
    elseif child:IsA("LocalScript") then
        if hasSubChild then
            fs.writeDir(newDir)
            fs.writeFile(`{newDir}/init.client.luau`, child.Source)

            for _, subChild in child:GetChildren() do
                create(subChild, newDir)
            end
        else
            fs.writeFile(`{newDir}.client.luau`, child.Source)
        end
    else
        fs.writeFile(`{newDir}.rbxm`, roblox.serializeModel({child}))
    end
end

while true do
    stdio.write(stdio.color("reset"))
    stdio.write("\nWrite path to RBXL: ")

    local path = stdio.readLine():gsub("\r\n", "")
    local isFile = fs.isFile(path)

    if not isFile then
        stdio.write(stdio.color("red"))
        stdio.write(`"{path}" is not a valid path. Try again.\n`)
        continue
    end

    stdio.write(`"{path}" successfuly found.\n`)
    stdio.write(`Write services to convert: `)

    local services = string.split(stdio.readLine():gsub("\r\n", ""), " ")

    stdio.write("\n")

    local place = fs.readFile(path)
    local game = roblox.deserializePlace(place)

    fs.writeDir("./src")

    for _, serviceName in if services[1] == "all" then allServices else services do
        local service = game:FindFirstChild(serviceName)

        if service then
            local dir = `./src/{service.Name}`

            fs.writeDir(dir)

            for _, child in service:GetChildren() do
                create(child, dir)
            end

            stdio.write(stdio.color("green"))
            stdio.write(`<{serviceName}> created successfully.\n`)
        else
            stdio.write(stdio.color("red"))
            stdio.write(`<{serviceName}> service does not exist or could not be found.\n`)
        end
    end

    stdio.write(stdio.color("reset"))
end