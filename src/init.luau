
-- This just loads the CoreRuntime.HWI file, then lets the core runtime take over from there
-- EXPECTED FILE SHAPE: "core.hwi.luau", ".chwi.luau"
-- The chwi contents are passed as the argv node to the CoreRuntime

--[[
local Bookstrapper = require("./Bookstrapper")
Bookstrapper:Initialize("Hawaii.Bootstrapper")
]]--

Bookstrapper = {}

local PackageIO = require("./PackageIO")
local Base64 = require("./Base64")
local process = require("@lune/process")
local URI = require("./URI")

local ImportEngine = require("./ImportEngine")
local PackageContent = require("./.chwi.luau")

local function Depackage(source: string)
	local rawB64 = string.gsub(source, "\n", "")
	local stream = buffer.fromstring(rawB64)
	return Base64.decode(stream)
end

local chwiPackage = PackageIO.CHWIReader(Depackage(PackageContent))

-- The CorePackage contains code to pick itself up from an external entry, the entry point is known as the
-- "starter"

local context = ImportEngine.fromCHWI(chwiPackage)
local sysPkg = context.Packages["Hawaii.System"]

if sysPkg then
	ImportEngine.setExport(context, sysPkg, "/FFI/Bootstrapper.luau", {
		Bookstrapper = Bookstrapper,
		PackageIO = PackageIO,
		URI = URI
	})
end

local argv = process.args
process.exit(context:Run(argv))