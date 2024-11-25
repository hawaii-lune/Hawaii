
-- This just loads the CoreRuntime.HWI file, then lets the core runtime take over from there
-- EXPECTED FILE SHAPE: "core.hwi.luau", ".chwi.luau"
-- The chwi contents are passed as the argv node to the CoreRuntime

--[[
local Bookstrapper = require("./Bookstrapper")
Bookstrapper:Initialize("Hawaii.Bootstrapper")
]]--

Bookstrapper = {}

local CHWI = require("./CHWI")
local Base64 = require("./Base64")
local process = require("@lune/process")

local ImportEngine = require("./ImportEngine")
local PackageContent = require("./.chwi.luau")

local function Depackage(source: string)
	local rawB64 = string.gsub(source, "\n", "")
	local stream = buffer.fromstring(rawB64)
	return Base64.decode(stream)
end

local chwiPackage = CHWI(Depackage(PackageContent))

-- The CorePackage contains code to pick itself up from an external entry, the entry point is known as the
-- "starter"

local context = ImportEngine.Public.fromCHWI(chwiPackage)
local sysPkg = context.Packages["Hawaii.System"]

ImportEngine.setExport(context, sysPkg, "/FFI/Bootstrapper.luau", {
	ImportEngine = ImportEngine.Public,
	Bookstrapper = Bookstrapper,
	-- TODO: allow these dependencies into system
	-- HWI = require("./HWI")
	-- CHWI = CHWI
})

print(context.Packages["Hawaii.System"].Modules["/FFI/Bootstrapper.luau"].Bookstrapper)

local argv = process.args
context:Run(argv)