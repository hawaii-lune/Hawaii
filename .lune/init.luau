-- Quick and dirty script to build packages
-- when Runtime can successfully build itself,
-- this can be scrapped

-- Location of package
local TO_BUILD = "./Packages/Hawaii.Runtime/src"

-- How wide to output the Base64 formatted HWI files
local COLUMN_SIZE = 80

-- Force rebuild the /build/directory
local ALWAYS_REBUILD = false

-- Set Luau compile options to "RELEASE"
local TARGET_RELEASE = false

-- Automatically debug the output object
local AUTO_DEBUG = true

-- Enables generation of an executable
-- This should remain disabled for now as this might not play nice
-- with antivirus solutions
local ENABLE_PROC_GEN = false

local serde = require("@lune/serde")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local Base64 = require("./Base64")
local process = require("@lune/process")
local streamblobs = {"HWI\x00\x0EHawaii.Runtime\7\17/source/init.luau\0"}

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

local function funcWrap(source)
	return `return function(import, exports, package) {source} end`
end

local objSize = 0
local function buildDirectoryTree(dir, cwd, attach)
	cwd = cwd or "/source"
	attach = attach or {}

	for _, file in fs.readDir(dir) do
		if fs.isDir(`{dir}/{file}`) then
			buildDirectoryTree(`{dir}/{file}`, `{cwd}/{file}`, attach)
		else
			attach[`{cwd}/{file}`] = funcWrap(fs.readFile(`{dir}/{file}`))
			objSize += 1
		end
	end

	return attach
end

local objects = buildDirectoryTree(TO_BUILD)
table.insert(streamblobs, writeULEB128(objSize))

for objectName, content in objects do
	table.insert(streamblobs, `{writeULEB128(#objectName)}{objectName}`)
	local bytecode = luau.compile(content, {
		optimizationLevel = if TARGET_RELEASE then 2 else 1,
		coverageLevel = 0,
		debugLevel = if TARGET_RELEASE then 0 else 1
	})

	local contentCompressed = serde.compress("zlib", bytecode)
	table.insert(streamblobs, writeULEB128(#contentCompressed))
	table.insert(streamblobs, contentCompressed)
end

local hwiFile = Base64.encode(buffer.fromstring(table.concat(streamblobs)))
local size = buffer.len(hwiFile)
-- now we need to process the .core.hwi.luau file into a base64 string

local lines = math.ceil(size / COLUMN_SIZE)
local sections = table.create(lines)
for i = 1, lines do
	local lowBound = (i-1) * COLUMN_SIZE
	local highBound = math.min(size, i * COLUMN_SIZE)

	sections[i] = buffer.readstring(hwiFile, lowBound, highBound - lowBound)
end

-- clone exports in Hawaii.RuntimeBuilder to /build
if ALWAYS_REBUILD or not fs.isDir("build") then fs.copy("Packages/Hawaii.RuntimeBuilder/exports", "build", ALWAYS_REBUILD) end
fs.writeFile("build/Hawaii.Runtime.hwi", table.concat(streamblobs))
fs.writeFile("build/core.hwi.luau", `return ([[\n{table.concat(sections, "\n")}\n]])`)

if ENABLE_PROC_GEN then
	warn("Process Generation is currently unstable and may produce unreliable results")
	
	process.spawn("darklua", {"process", "build/init.luau", "build/out/a.luau"}, {
		stdio = "inherit"
	})
	process.spawn("lune", {"build", "-t", "win-x86_64", "-o", "build/out/hawaii.exe", "build/out/proc.luau"}, {
		stdio = "inherit"
	})
end

if AUTO_DEBUG then
	print("Built Runtime.hwi, debugging is enabled. Debugging Hawaii...")
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