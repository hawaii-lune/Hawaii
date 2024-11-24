-- Quick and dirty script to build packages
-- when Runtime can successfully build itself,
-- this can be scrapped

local TO_BUILD = "./Packages/Hawaii.Runtime/src"
local COLUMN_SIZE = 80

local serde = require("@lune/serde")
local fs = require("@lune/fs")
local Base64 = require("./Base64")

local sourcePath = "/source/init.luau"

local streamblobs = {"HWI\x00\x0EHawaii.Runtime\9\x69\xF2\x3C\xF2\xB1\x9B\x8C\xA7\xE1\xBA\x2D\xDE\xA4\x16\x64\x59\0"}

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

local HASH_WIDTH = 32
local function hashEncode(hash)
	local hashBytes = {}
	for i = 1, HASH_WIDTH - 1, 2 do
		local digit = tonumber(string.sub(hash, i, i+1), 16)
		table.insert(hashBytes, string.char(digit))
	end

	return table.concat(hashBytes)
end

for objectName, content in objects do
	local objectNameHash = serde.hash("sha3-256", objectName)
	table.insert(streamblobs, `{writeULEB128(#objectName)}{objectName}`)
	table.insert(streamblobs, `{hashEncode(objectNameHash)}`)
	table.insert(streamblobs, writeULEB128(#content))
	table.insert(streamblobs, content)
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
fs.copy("Packages/Hawaii.RuntimeBuilder/exports", "build", true)

fs.writeFile("build/Hawaii.Runtime.hwi", table.concat(streamblobs))
fs.writeFile("build/core.hwi.luau", `return ([[\n{table.concat(sections, "\n")}\n]])`)

local AUTO_DEBUG = true
if AUTO_DEBUG then
	print("Built Runtime.hwi, debugging is enabled. Debugging Hawaii...")
	local process = require("@lune/process")
	process.spawn("lune", {"run",  "build"}, {
		stdio = "inherit"
	})
end