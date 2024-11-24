-- Starter script, this sets up a local import context for the package then
-- starts the actual runtime.

local luau = require("@lune/luau")
local hwi

local function HWI_LOADMODULE(path)
	local hashed = hwi.config.hashed
	local compiled = hwi.config.compiled
	local native = hwi.config.native

	local object = if hashed then hwi.objects[hwi.hashes[path]] else hwi.objects[path]
	if not object then error(`object {path} not found`) end

	local bytecode = buffer.tostring(object:Open())
	if not compiled then
		bytecode = luau.compile(bytecode, {
			optimizationLevel = 2,
			coverageLevel = 0,
			debugLevel = 1
		})
	end
	
	local callmangle = luau.load(bytecode, {
		debugName = `@{hwi.name}/{path}`,
		codegenEnabled = native
	})

	return callmangle()(nil, {}, package)
end

function exports.__STANDALONE_ENTRY(corePackage, buildPackage)
	-- from here, we need to set up the import and export commands
	-- for navigating between the package

	-- to begin with, we'll load objects in directly using a method called HWI_LOADMODULE
	-- then let the other modules handle it from there
	hwi = corePackage
	local realImport = HWI_LOADMODULE("/source/Import.luau")
	local importContext = realImport.fromHWI(corePackage)
	importContext.loadmodule("/source/RuntimeMain/init.luau").loadCHWI(buildPackage)
end

return exports