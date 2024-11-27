local serde = require("@lune/serde")
local luau = require("@lune/luau")
local Types = require("./Types")
local BasicTypes = require("./BasicTypes")
local VersionConfig = require("./VersionConfig")

local OBJECT_TYPE_PATH_MAP = {
	source = "/source",
	object = "/objects"
}

local function allocateWriterBuffer(
	pkgName,
	entryName,
	s1: number, s2: number,
	contentSizes: {number},
	sumOffset: number?
)
	-- computes the size to allocate, then we can just write data to it
	local pkl, enl = string.len(pkgName), string.len(entryName)

	local sum = (sumOffset or 0)
		+ BasicTypes.ULEB128Size(pkl) + pkl
		+ BasicTypes.ULEB128Size(enl) + enl
		+ BasicTypes.ULEB128Size(s1)
		+ BasicTypes.ULEB128Size(s2)
	for _, num in contentSizes do
		sum += BasicTypes.ULEB128Size(num) + num
	end

	return buffer.create(sum)
end

local function funcWrap(source: string): string
	return `return function(import, exports, package) {source} end`
end

local function packSourceFile(options: Types.HWIConfig, source: string): buffer
	-- for now, always targets debug performance
	source = funcWrap(source)

	if options.compiled then
		source = luau.compile(source, {
			optimizationLevel = 1,
			coverageLevel = 0,
			debugLevel = 1
		})
	end

	return buffer.fromstring(source)
end

local function compress(stream: buffer): buffer
	return buffer.fromstring(serde.compress("zlib", stream))
end

local function getBitFlag(self: Types.HWIWriter)
	return
		(if self.config.compressed then 1 else 0)
		+ (if self.config.compiled then 2 else 0)
		+ (if self.config.native then 4 else 0)
end

local function bufferWriter(self: Types.HWIWriter): buffer
	if self.content then return self.content end
	if not self.config.entry then error("No entry point defined on package, cant be written") end

	local sizes = {}
	local files = {}
	local s1, s2 = 0, 0

	for alias, dependency in self.config.dependencies do
		table.insert(sizes, string.len(alias))
		table.insert(sizes, string.len(dependency))
		s1 += 1
	end

	local COMPRESS_OBJECTS = self.config.compressed
	for fileName, file in self.objects do
		table.insert(sizes, string.len(fileName))

		--TODO: make this dynamic based on output directory
		if string.sub(fileName, 1, 8) == "/source/" then
			file = packSourceFile(self.config, buffer.tostring(file))
		end

		if COMPRESS_OBJECTS then
			file = compress(file)
		end

		table.insert(sizes, buffer.len(file))
		files[fileName] = file
		s2 += 1
	end

	local writer = allocateWriterBuffer(
		self.name, self.config.entry,
		s1, s2, sizes,
		--HWI\0 BITFLAG
		5
	)
	buffer.writestring(writer, 0, `HWI`)
	buffer.writeu8(writer, 3, VersionConfig.HWI_PREFER)
	local offsetPointer = {offset = 4}
	

	BasicTypes.InsertString(writer, self.name, offsetPointer)
	buffer.writeu8(writer, offsetPointer.offset, getBitFlag(self))
	offsetPointer.offset += 1
	BasicTypes.InsertString(writer, self.config.entry, offsetPointer)
	BasicTypes.InsertULEB128(writer, s1, offsetPointer)

	for alias, dependecy in self.config.dependencies do
		BasicTypes.InsertString(writer, alias, offsetPointer)
		BasicTypes.InsertString(writer, dependecy, offsetPointer)
	end

	BasicTypes.InsertULEB128(writer, s2, offsetPointer)

	for fileName, fileContent in files do
		BasicTypes.InsertString(writer, fileName, offsetPointer)
		BasicTypes.InsertBuffer(writer, fileContent, offsetPointer)
	end

	self.content = writer
	return writer
end

return function(packageName: string)
	local pkg = {}
	pkg.name = packageName
	pkg.config = {
		compiled = false,
		compressed = false,
		native = false,
		dependencies = {}
	}
	pkg.objects = {}

	function pkg.AttachPrebuiltHWI(self: Types.HWIWriter, prebuild: buffer)
		-- adds an existing HWI file to the writer
		-- TODO: this should validate the HWI object
		pkg.content = prebuild
	end

	function pkg.AddObject(self: Types.HWIWriter, objType: Types.ObjectType, path: string, stream: buffer)
		local directory = OBJECT_TYPE_PATH_MAP[objType] or error(`Invalid path type {objType}`)
		pkg.objects[`{directory}/{path}`] = stream
	end

	function pkg.SetEntryPath(self: Types.HWIWriter, path: string)
		local dir = `{OBJECT_TYPE_PATH_MAP.source}/{path}`
		if not self.objects[dir] then
			error(`source file {path} not present in objects`)
		end

		self.config.entry = dir
	end

	pkg.ToBuffer = bufferWriter
	return pkg
end
