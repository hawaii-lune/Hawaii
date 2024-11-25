-- builds child HWI files then merges them together into a CHWI
-- this still isn't the final impl of this but done so i can at least get a start on it
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Base64 = require("./Base64.luau")
local process = require("@lune/process")

local ENTRY_POINT = "Packages/Hawaii.CLI"

-- How wide to output the Base64 formatted HWI files
local COLUMN_SIZE = 80

-- Force rebuild the /build/directory
local ALWAYS_REBUILD = true

-- Set Luau compile options to "RELEASE"
local TARGET_RELEASE = false

-- Automatically debug the output object
local AUTO_DEBUG = true

-- Enables generation of an executable
-- This should remain disabled for now as this might not play nice
-- with antivirus solutions
local ENABLE_PROC_GEN = false

local function funcWrap(source)
	return `return function(import, exports, package) {source} end`
end

local function buildDirectoryTree(dir, cwd, attach): {{path: string, content: string}}
	attach = attach or {}

	for _, file in fs.readDir(dir) do
		if fs.isDir(`{dir}/{file}`) then
			buildDirectoryTree(`{dir}/{file}`, `{cwd}/{file}`, attach)
		else
			table.insert(attach, {
				path = `{cwd}/{file}`,
				content = fs.readFile(`{dir}/{file}`)
			})
		end
	end

	return attach
end

local function writeULEB128(n)
	local result = {}
	
	repeat
			local byte = bit32.band(n, 0x7F)  -- Extract the 7 least significant bits
			n = bit32.rshift(n, 7)           -- Shift right by 7 bits
			if n ~= 0 then        -- If there are still bits left, set the continuation bit
					byte = bit32.bor(byte, 0x80)
			end
			table.insert(result, string.char(byte)) -- Append the byte to the result
	until n == 0

	-- Convert the result table to a string
	return table.concat(result, "")
end

local function writeULEBString(s)
	local len = writeULEB128(#s)
	return table.concat({len, s})
end

local function addObjects(writeTo, dir, rel)
	if not fs.isDir(rel) then
		error(`cannot find directory {rel}`)
	end

	local objects = buildDirectoryTree(rel, dir)
	for _, object in objects do
		local objectHeader = {}
		table.insert(objectHeader, writeULEBString(object.path))
		local content = object.content

		if dir == "/source" then
			content = luau.compile(funcWrap(content), {
				optimizationLevel = if TARGET_RELEASE then 2 else 1,
				coverageLevel = 0,
				debugLevel = if TARGET_RELEASE then 0 else 1
			})
		end

		local compressed = serde.compress("zlib", content)
		table.insert(objectHeader, writeULEBString(compressed))

		table.insert(writeTo, table.concat(objectHeader))
	end
end

local function buildHWI(config)
	local buffer = {"HWI\x00"}
	table.insert(buffer, writeULEBString(config.name))
	-- entry point is always /source/init.luau
	table.insert(buffer, "\7\17/source/init.luau")
	table.insert(buffer, writeULEB128(#config.resolvedDependencies))

	-- encode dependency tree
	for _, dependency in config.resolvedDependencies do
		table.insert(buffer, writeULEBString(dependency.alias))
		table.insert(buffer, writeULEBString(dependency.obj))
	end

	local directories = config.directories
	if not directories then error("no buildable objects") end
	local sourceDirRel, objectsDirRel = directories.source, directories.objects
	
	local fChunk = {}
	if sourceDirRel then addObjects(fChunk, "/source", `{config.location}/{sourceDirRel}`) end
	if objectsDirRel then addObjects(fChunk, "/objects", `{config.location}/{objectsDirRel}`) end
	table.insert(buffer, writeULEB128(#fChunk))
	table.insert(buffer, table.concat(fChunk))
	return table.concat(buffer)
end

-- to begin with, lets resolve the dependency tree so we're not repeating ourselves with the build steps
local buildchain = {}

local function buildDependencyTree(packageFolder: string)
	if not fs.isFile(`{packageFolder}/hawaii.toml`) then
		error(`cant hawaii.toml config file in object {packageFolder}`)
	end

	local config = serde.decode("toml", fs.readFile(`{packageFolder}/hawaii.toml`))
	config.resolvedDependencies = {}
	config.location = packageFolder
	
	buildchain[config.name] = config
	if config.dependencies then
		for k, v in config.dependencies do
			-- resolve child dependencies
			local actualPackageName = buildDependencyTree(`{packageFolder}/{v.path}`)
			table.insert(config.resolvedDependencies, {alias = k, obj = actualPackageName})
		end
	end
		
	return config.name
end

buildDependencyTree(ENTRY_POINT)
local HWIFileStreams = {}
if ALWAYS_REBUILD or not fs.isDir("build") then fs.copy("Packages/Hawaii.Bootstrapper/exports", "build", ALWAYS_REBUILD) end

for package, configs in buildchain do
	local stream = buildHWI(configs)
	fs.writeFile(`build/{package}.hwi`, stream)
	table.insert(HWIFileStreams, {name = package, obj = serde.compress("zlib", stream)})
end

-- pack streams into CHWI
local chwiBuffer = {"CHWI\0\6Hawaii\x0AHawaii.CLI"}
table.insert(chwiBuffer, writeULEB128(#HWIFileStreams))
for _, stream in HWIFileStreams do
	table.insert(chwiBuffer, "\0")
	table.insert(chwiBuffer, writeULEBString(stream.name))
	table.insert(chwiBuffer, writeULEBString(stream.obj))
end

local chwi = table.concat(chwiBuffer)
fs.writeFile(`build/Hawaii.chwi`, chwi)

local function writeBin(stream, filePath)
	stream = Base64.encode(buffer.fromstring(stream))
	local size = buffer.len(stream)
	local lines = math.ceil(size / COLUMN_SIZE)
	local sections = table.create(lines)

	for i = 1, lines do
		local lowBound = (i-1) * COLUMN_SIZE
		local highBound = math.min(size, i * COLUMN_SIZE)

		sections[i] = buffer.readstring(stream, lowBound, highBound - lowBound)
	end

	fs.writeFile(filePath, `return ([[\n{table.concat(sections, "\n")}\n]])`)
end

-- clone exports in Hawaii.RuntimeBuilder to /build
writeBin(chwi, "build/.chwi.luau")

if ENABLE_PROC_GEN then
	warn("Process Generation is currently unstable and may produce unreliable results")
	
	process.spawn("darklua", {"process", "build/init.luau", "build/out/a.luau"}, {
		stdio = "inherit"
	})
	process.spawn("lune", {"build", "-t", "win-x86_64", "-o", "build/out/hawaii.exe", "build/out/a.luau"}, {
		stdio = "inherit"
	})
end

if AUTO_DEBUG then
	print("Built Hawaii.System.hwi, debugging is enabled. Debugging Hawaii...")
	if ENABLE_PROC_GEN then
		process.spawn("build/out/hawaii",  {}, {
			stdio = "inherit"
		})
	else
		process.spawn("lune", {"run",  "build"}, {
			stdio = "inherit"
		})
	end
end