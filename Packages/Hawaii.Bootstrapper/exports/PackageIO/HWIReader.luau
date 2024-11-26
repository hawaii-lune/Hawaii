-- HWI package.
local serde = require("@lune/serde")
local BasicTypes = require("./BasicTypes")
local Types = require("./Types")
local VersionConfig = require("./VersionConfig")

local function HWIObject(): Types.HWIObject
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

local function newHWI(name: string): Types.HWIPackage
	local hwi = {} :: Types.HWIPackage
	hwi.name = name
	hwi.config = {
		compressed = false,
		compiled = false,
		native = false,
		dependencies = {}
	}
	hwi.objects = {}
	return hwi
end

return function(b: buffer): Types.HWIPackage
	if buffer.readstring(b, 0, 3) ~= "HWI" then
		error("bad magic header")
	end

	local v = buffer.readu8(b, 3)
	if v < VersionConfig.HWI_MIN or v > VersionConfig.HWI_MAX then
		error(`version out of range {VersionConfig.HWI_MIN} <= {v} < {VersionConfig.HWI_MAX}`)
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

	local pkg: Types.HWIPackage = newHWI(packageName)
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