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

-- Maps service names to their Roblox DataModel class names (when different)
local SERVICE_CLASS_OVERRIDES = {
	Workspace = "Workspace",
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

-- Serializes an attribute value into the Rojo JSON format
local function serializeAttributeValue(value: any): string?
	local t = typeof(value)

	if t == "boolean" then
		return tostring(value)
	elseif t == "number" then
		-- Distinguish between integers and floats
		if value == math.floor(value) and math.abs(value) < 2^53 then
			return tostring(math.floor(value))
		else
			return tostring(value)
		end
	elseif t == "string" then
		-- Escape special characters in JSON strings
		local escaped = value
			:gsub("\\", "\\\\")
			:gsub('"', '\\"')
			:gsub("\n", "\\n")
			:gsub("\r", "\\r")
			:gsub("\t", "\\t")
		return '"' .. escaped .. '"'
	elseif t == "Vector3" then
		return '{"Vector3": [' .. value.X .. ", " .. value.Y .. ", " .. value.Z .. "]}"
	elseif t == "Vector2" then
		return '{"Vector2": [' .. value.X .. ", " .. value.Y .. "]}"
	elseif t == "Color3" then
		-- Rojo expects Color3 as an array of [R, G, B] floats (0–1)
		return '{"Color3": [' .. value.R .. ", " .. value.G .. ", " .. value.B .. "]}"
	elseif t == "UDim" then
		return '{"UDim": [' .. value.Scale .. ", " .. value.Offset .. "]}"
	elseif t == "UDim2" then
		return '{"UDim2": [[' .. value.X.Scale .. ", " .. value.X.Offset .. "], [" .. value.Y.Scale .. ", " .. value.Y.Offset .. "]]}"
	elseif t == "Rect" then
		return '{"Rect": [[' .. value.Min.X .. ", " .. value.Min.Y .. "], [" .. value.Max.X .. ", " .. value.Max.Y .. "]]}"
	elseif t == "NumberRange" then
		return '{"NumberRange": [' .. value.Min .. ", " .. value.Max .. "]}"
	elseif t == "CFrame" then
		local p = value.Position
		local rx, ry, rz = value:ToEulerAnglesXYZ()
		return '{"CFrame": [[' .. p.X .. ", " .. p.Y .. ", " .. p.Z .. "], [" .. rx .. ", " .. ry .. ", " .. rz .. "]]}"
	elseif t == "BrickColor" then
		return '{"BrickColor": ' .. value.Number .. "}"
	else
		-- Unsupported type; skip this attribute
		return nil
	end
end

-- Builds a $attributes JSON block from an instance's attribute table
local function buildAttributesBlock(instance: Instance, indent: string): string?
	local attrs = instance:GetAttributes()
	if not next(attrs) then
		return nil
	end

	local entries = {}
	for key, value in attrs do
		local serialized = serializeAttributeValue(value)
		if serialized then
			table.insert(entries, indent .. '\t"' .. key .. '": ' .. serialized)
		else
			writeColored("yellow", `  [WARN] Attribute "{key}" on "{instance.Name}" has unsupported type "{typeof(value)}", skipping.\n`)
		end
	end

	if #entries == 0 then
		return nil
	end

	return indent .. '"$attributes": {\n' .. table.concat(entries, ",\n") .. "\n" .. indent .. "}"
end

-- Builds a $tags JSON block from an instance's tag list
local function buildTagsBlock(instance: Instance, indent: string): string?
	local tags = instance:GetTags()
	if #tags == 0 then
		return nil
	end

	local entries = {}
	for _, tag in tags do
		local escaped = tag:gsub("\\", "\\\\"):gsub('"', '\\"')
		table.insert(entries, '"' .. escaped .. '"')
	end

	return indent .. '"$tags": [' .. table.concat(entries, ", ") .. "]"
end

-- Generates a default.project.json compatible with LSP
local function generateProjectJson(selectedServices: { string }, projectName: string, game: Instance)
	-- Build the tree entries for each selected service
	local serviceEntries = {}
	for _, serviceName in selectedServices do
		local className = SERVICE_CLASS_OVERRIDES[serviceName] or serviceName
		local service = game:FindFirstChild(serviceName)

		local extraFields = {}

		if service then
			local attrsBlock = buildAttributesBlock(service, "\t\t\t")
			if attrsBlock then
				table.insert(extraFields, attrsBlock)
			end

			local tagsBlock = buildTagsBlock(service, "\t\t\t")
			if tagsBlock then
				table.insert(extraFields, tagsBlock)
			end
		end

		local entry = '\t\t"' .. serviceName .. '": {\n'
			.. '\t\t\t"$className": "' .. className .. '",\n'
			.. '\t\t\t"$path": "src/' .. serviceName .. '"'

		if #extraFields > 0 then
			entry = entry .. ",\n" .. table.concat(extraFields, ",\n") .. "\n"
		else
			entry = entry .. "\n"
		end

		entry = entry .. "\t\t}"
		table.insert(serviceEntries, entry)
	end

	local treeBody = table.concat(serviceEntries, ",\n")

	local json = "{\n"
		.. '\t"name": "' .. projectName .. '",\n'
		.. '\t"tree": {\n'
		.. '\t\t"$className": "DataModel",\n'
		.. treeBody .. "\n"
		.. "\t}\n"
		.. "}"

	fs.writeFile("./default.project.json", json)
	writeColored("green", `  [OK] "default.project.json" generated successfully.\n`)
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

-- Prompts for the project name used in default.project.json
local function promptProjectName(): string
	writeColored("reset", `Project name (default: "my-project"): `)
	local name = readLineClean()

	if name == "" then
		return "my-project"
	end

	return name
end

-- Main loop
while true do
	local filePath = promptFilePath()
	local selectedServices = promptServices()
	local projectName = promptProjectName()

	stdio.write("\n")

	local rawPlace = fs.readFile(filePath)
	local game = roblox.deserializePlace(rawPlace)

	exportServices(game, selectedServices)
	generateProjectJson(selectedServices, projectName, game)
	writeColored("reset", "\nExport complete.\n")
end
