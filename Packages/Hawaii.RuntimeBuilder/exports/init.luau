
-- This just loads the CoreRuntime.HWI file, then lets the core runtime take over from there
-- EXPECTED FILE SHAPE: "core.hwi.luau", ".chwi.luau"
-- The chwi contents are passed as the argv node to the CoreRuntime

local luau = require("@lune/luau")
local HWI = require("./HWI")
local Base64 = require("./Base64")

local CoreHWIContent = require("./core.hwi")
local PackageContentAvailable, PackageContent = pcall(require, "./.chwi")

if not PackageContentAvailable then
	warn(".chwi.luau is empty")
end

local function Depackage(source: string)
	local rawB64 = string.gsub(source, "[^A-Za-z0-9+/=]", "")
	local stream = buffer.fromstring(rawB64)
	return Base64.decode(stream)
end

-- The CorePackage contains code to pick itself up from an external entry, the entry point is known as the
-- "starter"
local now = os.clock()
local corePackage = HWI.fromStream(Depackage(CoreHWIContent))
local entryFile = corePackage.objects[corePackage.config.entry]

local bytecode = buffer.tostring(entryFile:Open())
if not corePackage.config.compiled then
	bytecode = luau.compile(bytecode, {
		optimizationLevel = 2,
		coverageLevel = 0,
		debugLevel = 1
	})
end

local callmangle = luau.load(bytecode, {
	debugName = `{corePackage.name}{entryFile.filePath}`,
	codegenEnabled = corePackage.config.native
})

local exports = callmangle()
exports(nil, {}, {
	objects = corePackage.objects
}).__STANDALONE_ENTRY(corePackage, PackageContentAvailable and Depackage(PackageContent))

print(os.clock() - now)