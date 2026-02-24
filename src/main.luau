--!strict
-- System by @SayderKonkest, 2026

local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local roblox = require("@lune/roblox")

-- Default Roblox services available for export
local DEFAULT_SERVICES = {
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
	"TextChatService",
}

-- Instances that behave like folders (create a directory and process children)
local FOLDER_LIKE_CLASSES = {
	Folder = true,
	StarterCharacterScripts = true,
	StarterPlayerScripts = true,
}

local function writeColored(color: string, message: string)
	stdio.write(stdio.color(color))
	stdio.write(message)
end

local function readLineClean(): string
	return stdio.readLine():gsub("\r\n", "")
end

local function processChildren(instance: Instance, parentDir: string)
	-- Forward declaration required since processInstance is recursive
end

-- Processes a Script instance based on its RunContext
local function processScript(script: Instance, dir: string)
	local hasChildren = #script:GetChildren() > 0
	local runContext = (script :: any).RunContext.Name

	if runContext == "Client" then
		fs.writeFile(`{dir}.client.luau`, (script :: any).Source)
		if hasChildren then
			for _, child in script:GetChildren() do
				processChildren(child, dir)
			end
		end
	elseif runContext == "Server" or runContext == "Legacy" or runContext == "Plugin" then
		if hasChildren then
			fs.writeDir(dir)
			fs.writeFile(`{dir}/init.server.luau`, (script :: any).Source)
			for _, child in script:GetChildren() do
				processChildren(child, dir)
			end
		else
			fs.writeFile(`{dir}.server.luau`, (script :: any).Source)
		end
	end
end

-- Recursively processes any instance, building the output file structure
local function processInstance(instance: Instance, parentDir: string)
	local instanceDir = `{parentDir}/{instance.Name}`
	local hasChildren = #instance:GetChildren() > 0

	local function writeChildrenTo(targetDir: string)
		for _, child in instance:GetChildren() do
			processInstance(child, targetDir)
		end
	end

	if FOLDER_LIKE_CLASSES[instance.ClassName] then
		fs.writeDir(instanceDir)
		if hasChildren then
			writeChildrenTo(instanceDir)
		end
	elseif instance:IsA("ModuleScript") then
		fs.writeDir(instanceDir)
		fs.writeFile(`{instanceDir}/init.luau`, (instance :: any).Source)
		if hasChildren then
			writeChildrenTo(instanceDir)
		end
	elseif instance:IsA("LocalScript") then
		if hasChildren then
			fs.writeDir(instanceDir)
			fs.writeFile(`{instanceDir}/init.client.luau`, (instance :: any).Source)
			writeChildrenTo(instanceDir)
		else
			fs.writeFile(`{instanceDir}.client.luau`, (instance :: any).Source)
		end
	elseif instance.ClassName == "Script" then
		processScript(instance, instanceDir)
	else
		-- Instances without script source are serialized as binary model files
		fs.writeFile(`{instanceDir}.rbxm`, roblox.serializeModel({ instance }))
	end
end

-- Resolves the forward declaration with a closure
processChildren = function(instance: Instance, parentDir: string)
	processInstance(instance, parentDir)
end

-- Exports the selected services from the place file into ./src
local function exportServices(game: Instance, selectedServices: { string })
	if not fs.isDir("./src") then
		fs.writeDir("./src")
	end

	for _, serviceName in selectedServices do
		local service = game:FindFirstChild(serviceName)

		if not service then
			writeColored("red", `  [ERROR] Service "{serviceName}" not found.\n`)
			continue
		end

		local serviceDir = `./src/{serviceName}`
		if not fs.isDir(serviceDir) then
			fs.writeDir(serviceDir)
		end

		for _, child in service:GetChildren() do
			processInstance(child, serviceDir)
		end

		writeColored("green", `  [OK] "{serviceName}" exported successfully.\n`)
	end
end

-- Prompts and validates the path to the .rbxl file
local function promptFilePath(): string
	while true do
		writeColored("reset", "\nPath to .rbxl file: ")
		local path = readLineClean()

		if fs.isFile(path) then
			writeColored("reset", `File found: "{path}"\n`)
			return path
		end

		writeColored("red", `Invalid path: "{path}". Please try again.\n`)
	end
end

-- Prompts which services to export ("all" to select every default service)
local function promptServices(): { string }
	writeColored("reset", `Services to export (space-separated, or "all"): `)
	local input = readLineClean()
	local selected = string.split(input, " ")

	if selected[1] == "all" then
		return DEFAULT_SERVICES
	end

	return selected
end

-- Main loop
while true do
	local filePath = promptFilePath()
	local selectedServices = promptServices()

	stdio.write("\n")

	local rawPlace = fs.readFile(filePath)
	local game = roblox.deserializePlace(rawPlace)

	exportServices(game, selectedServices)

	writeColored("reset", "\nExport complete.\n")
end
