-- HWI package.
local HWI_FORMAT_MIN_VERSION, HWI_FORMAT_MAX_VERSION = 0, 0
local serde = require("@lune/serde")
local BasicTypes = require("./BasicTypes.luau")

type HWIObject = {
	compressed: boolean,
	filePath: string?,
	content: buffer,
	Open: (HWIObject) -> buffer
}

type HWIConfig = {
	--this should be json permitted objects

	entry: string?,
	compiled: boolean,
	compressed: boolean,
	native: boolean,
	dependencies: {[string]: string}
}

export type HWIPackage = {
	objects: {[string]: HWIObject},
	name: string,
	config: HWIConfig,
	export: {[string]: string}?, -- technically a HawaiiExport type but not really relevant here
	-- since you shouldn't be directly accessing this
	dependencies: {[string]: HWIPackage},
}

local function HWIObject(): HWIObject
	return {
		compressed = false,
		hash = nil,
		filePath = nil,
		content = nil,

		Open = function(self)
			local c = if self.compressed then serde.decompress("zlib", self.content) else self.content
			return buffer.fromstring(c)
		end
	}
end

local function newHWI(name: string): HWIPackage
	local hwi = {} :: HWIPackage
	hwi.name = name
	hwi.config = {
		compressed = false,
		compiled = false,
		native = false,
		dependencies = {}
	}
	hwi.objects = {}
	hwi.dependencies = {}
	return hwi
end

return function(b: buffer): HWIPackage
	if buffer.readstring(b, 0, 3) ~= "HWI" then
		error("bad magic header")
	end

	local v = buffer.readu8(b, 3)
	if v < HWI_FORMAT_MIN_VERSION or v > HWI_FORMAT_MAX_VERSION then
		error(`version {v} out of range {HWI_FORMAT_MIN_VERSION} - {HWI_FORMAT_MAX_VERSION}`)
	end

	local offsetPtr = {offset = 4}
	-- format spec
	-- file name
	-- config bitflag
	-- entry file
	-- dependencies
	-- file headers
	-- streams

	local packageName = BasicTypes.ReadString(b, offsetPtr)
	local configBitFlag = buffer.readu8(b, offsetPtr.offset)
	offsetPtr.offset+=1

	local config = {
		compressed = bit32.band(configBitFlag, 1) == 1,
		compiled = bit32.band(configBitFlag, 2) == 2,
		native = bit32.band(configBitFlag, 4) == 4
	}

	config.entry = BasicTypes.ReadString(b, offsetPtr)

	-- read dependencies
	local sizeDependencies = BasicTypes.ULEB128(b, offsetPtr)
	local dependencies = table.create(sizeDependencies)

	if sizeDependencies > 0 then
		for dID = 1, sizeDependencies do
			-- alias = actual package identifier in parent CHWI
			dependencies[BasicTypes.ReadString(b, offsetPtr)] = BasicTypes.ReadString(b, offsetPtr)
		end
	end
	config.dependencies = dependencies

	local pkg: HWIPackage = newHWI(packageName)
	pkg.config = config
	local sizeHeaders = BasicTypes.ULEB128(b, offsetPtr)

	if sizeHeaders > 0 then
		for headerID = 1, sizeHeaders do
			-- reads header
			-- fileName
			-- content size
			-- content

			local name = BasicTypes.ReadString(b, offsetPtr)
			local size = BasicTypes.ULEB128(b, offsetPtr)

			local content = buffer.create(size)
			buffer.copy(content, 0, b, offsetPtr.offset, size)
			offsetPtr.offset += size

			local obj = HWIObject()
			obj.compressed = pkg.config.compressed
			obj.filePath = name
			obj.content = content
			table.freeze(obj)
			
			pkg.objects[name] = obj
		end

		table.freeze(pkg.objects)
	end

	table.freeze(pkg)
	return pkg
end