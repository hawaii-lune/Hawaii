-- HWI package.
local HWI_FORMAT_MIN_VERSION, HWI_FORMAT_MAX_VERSION = 0, 0
local serde = require("@lune/serde")
local BasicTypes = require("./BasicTypes.luau")
local HWI = {}

type HWIObject = {
	compressed: boolean,
	hash: string?,
	filePath: string?,
	content: buffer,
	Open: (HWIObject) -> buffer
}

type HWIConfig = {
	--this should be json permitted objects

	entry: string?,
	hashed: boolean,
	compiled: boolean,
	compressed: boolean,
	native: boolean,
	dependencies: {[string]: string}
}

export type HWIPackage = {
	objects: {[string]: HWIObject},
	name: string,
	config: HWIConfig,
	hashes: {[string]: string},
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
			if self.compressed then
				return serde.decompress("zlib", self.content)
			end

			return self.content
		end
	}
end

function HWI.new(name: string): HWIPackage
	local hwi = {} :: HWIPackage
	hwi.name = name
	hwi.config = {
		compressed = false,
		hashed = false,
		compiled = false,
		native = false,
		dependencies = {}
	}
	hwi.objects = {}
	hwi.hashes = {}
	hwi.dependencies = {}
	return hwi
end

function HWI.fromStream(b: buffer): HWIPackage
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
	-- entry hash or file
	-- dependencies
	-- file headers, contain encoded hahses if applicable
	-- streams

	local packageName = BasicTypes.ReadString(b, offsetPtr)
	local configBitFlag = buffer.readu8(b, offsetPtr.offset)
	offsetPtr.offset+=1

	local config = {
		hashed = bit32.band(configBitFlag, 1) == 1,
		compressed = bit32.band(configBitFlag, 2) == 1,
		compiled = bit32.band(configBitFlag, 4) == 1,
		native = bit32.band(configBitFlag, 8) == 1
	}

	config.entry = if config.hashed then BasicTypes.Hash256(b, offsetPtr) else BasicTypes.ReadString(b, offsetPtr)

	-- read dependencies
	local sizeDependencies = BasicTypes.ULEB128(b, offsetPtr)
	local dependencies = table.create(sizeDependencies)

	if sizeDependencies > 0 then
		for dID = 1, sizeDependencies do
			dependencies[BasicTypes.ReadString(b, offsetPtr)] = BasicTypes.ReadString(b, offsetPtr)
		end
	end
	config.dependencies = dependencies

	local pkg: HWIPackage = HWI.new(packageName)
	pkg.config = config
	local hashed = pkg.config.hashed
	local sizeHeaders = BasicTypes.ULEB128(b, offsetPtr)

	if sizeHeaders > 0 then
		for headerID = 1, sizeHeaders do
			-- reads header
			-- fileName
			-- hash (if hashes present)
			-- content size
			-- content

			local name = BasicTypes.ReadString(b, offsetPtr)
			local hash

			if hashed then
				hash = BasicTypes.Hash256(b, offsetPtr)
				pkg.hashes[name] = hash
			end

			local size = BasicTypes.ULEB128(b, offsetPtr)

			local content = buffer.create(size)
			buffer.copy(content, 0, b, offsetPtr.offset, size)
			offsetPtr.offset += size

			local obj = HWIObject()
			obj.compressed = pkg.config.compressed
			obj.hash = hash
			obj.filePath = name
			obj.content = content
			table.freeze(obj)
			
			pkg.objects[hash or name] = obj
		end
	end

	return pkg
end

return HWI