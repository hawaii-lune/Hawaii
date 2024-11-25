
-- This just loads the CoreRuntime.HWI file, then lets the core runtime take over from there
-- EXPECTED FILE SHAPE: "core.hwi.luau", ".chwi.luau"
-- The chwi contents are passed as the argv node to the CoreRuntime

local luau = require("@lune/luau")
local HWI = require("./HWI")
local CHWI = require("./CHWI")
local Base64 = require("./Base64")

local ImportScript = require("./system.hwi.luau")
local PackageContentAvailable, PackageContent = pcall(require, "./.chwi.luau")

if not PackageContentAvailable then
	warn(".chwi.luau is empty")
end

local function Depackage(source: string)
	local rawB64 = string.gsub(source, "[^A-Za-z0-9+/=]", "")
	local stream = buffer.fromstring(rawB64)
	return Base64.decode(stream)
end

local corePackage = HWI(Depackage(ImportScript))
local chwiPackage = if PackageContentAvailable then CHWI(Depackage(PackageContent)) else nil

-- The CorePackage contains code to pick itself up from an external entry, the entry point is known as the
-- "starter"

local function HWI_LOADMODULE(path)
	local obj = corePackage.objects[path]
	local bytecode = buffer.tostring(obj:Open())

	if not corePackage.config.compiled then
		bytecode = luau.compile(bytecode, {
			optimizationLevel = 2,
			coverageLevel = 0,
			debugLevel = 1
		})
	end

	local callmangle = luau.load(bytecode, {
		debugName = `{corePackage.name}{obj.filePath}`,
		codegenEnabled = corePackage.config.native
	})

	return callmangle()(nil, {}, {
		objects = corePackage.objects
	})
end

local importEngine = HWI_LOADMODULE("/source/BootstrapperHook.luau")
local context = importEngine.newRuntimeContext()

if chwiPackage then
	context:loadCHWI(chwiPackage)
else
	print("RuntimeContext was loaded successfully, but no package is available")
end