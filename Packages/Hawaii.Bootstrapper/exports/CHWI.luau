local CHWI_FORMAT_MIN_VERSION, CHWI_FORMAT_MAX_VERSION = 0, 0
local serde = require("@lune/serde")
local BasicTypes = require("./BasicTypes.luau")
local HWI = require("./HWI.luau")

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

export type HWIPackageStream = {
	name: string,
	content: buffer,
	loadedPackage: HWI.HWIPackage?,
	Open: (HWIPackageStream) -> HWI.HWIPackage
} 

export type CHWIPackage = {
	name: string,
	entry: HWI.HWIPackage, -- entry package is loaded into context
	packages: {[string]: HWIPackageStream}
}

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
			end

			return pkg
		end
	}
end

return function(b: buffer): CHWIPackage
	if buffer.readstring(b, 0, 4) ~= "CHWI" then
		error("bad magic header")
	end

	local v = buffer.readu8(b, 4)
	if v < CHWI_FORMAT_MIN_VERSION or v > CHWI_FORMAT_MAX_VERSION then
		error(`version {v} out of range {CHWI_FORMAT_MIN_VERSION} - {CHWI_FORMAT_MAX_VERSION}`)
	end

	local offsetPtr = {offset = 4}
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
	local entryPoint = files[entryPoint]
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