local serde = require("@lune/serde")
local BasicTypes = require("./BasicTypes")
local HWI = require("./HWIReader")
local VersionConfig = require("./VersionConfig")

-- Object to load a CHWI file instead of a HWI
-- These are considerably easier to load since its effectively a list of HWI files and how to find them

-- Format:
-- CHWI header
-- Version byte (0)
-- CHWI name
-- Entry point name
-- Number of HWIs
-- [HWI Files]

--- HWIFiles
-- import type
-- 0: embedded
-- 1: imported - not enabled
-- package name
-- content or import path
local Types = require("./Types")

type CHWIFile = {}

local function HWIPackageStream(name: string, packageStream: buffer)
	return {
		name = name,
		content = packageStream,
		Open = function(self)
			local pkg = self.loadedPackage
			if not pkg then
				pkg = HWI(buffer.fromstring(serde.decompress("zlib", self.content)))
				self.loadedPackage = pkg

				if pkg.name ~= self.name then
					error("CHWI <> HWI name mismatch")
				end
			end

			return pkg
		end
	}
end

return function(b: buffer): Types.CHWIPackage
	if buffer.readstring(b, 0, 4) ~= "CHWI" then
		error("bad magic header")
	end

	local v = buffer.readu8(b, 4)
	if v < VersionConfig.CHWI_MIN or v > VersionConfig.CHWI_MAX then
		error(`version out of range {VersionConfig.CHWI_MIN} <= {v} < {VersionConfig.CHWI_MAX}`)
	end

	local offsetPtr = {offset = 5}
	local packageName = BasicTypes.ReadString(b, offsetPtr)
	local entryPoint = BasicTypes.ReadString(b, offsetPtr)
	local sizeHWIs = BasicTypes.ULEB128(b, offsetPtr)

	local files = {}
	if sizeHWIs > 0 then
		for hwiID = 1, sizeHWIs do
			local importType = buffer.readu8(b, offsetPtr.offset)
			offsetPtr.offset += 1
			if importType ~= 0 then
				error("Invalid import type")
			end

			local objectName = BasicTypes.ReadString(b, offsetPtr)
			local fileContent = buffer.fromstring(BasicTypes.ReadString(b, offsetPtr))
			local packageStream = HWIPackageStream(objectName, fileContent)
			files[objectName] = packageStream
		end
	end

	-- open the entry file
	entryPoint = files[entryPoint]
	if not entryPoint then
		error("no available entry point in package")
	end
	local pkg = entryPoint:Open()

	return {
		name = packageName,
		entry = pkg,
		packages = files
	}
end