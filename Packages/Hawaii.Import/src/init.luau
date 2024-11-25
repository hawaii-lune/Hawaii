-- Base import engine implementation

type HWI = {
	[string]: any
}

type ImportContext = {
	package: HWI,
	lazyDependencies: {[string]: ImportContext},
	isRunnable: boolean,
	entrymod: string,
	modules: {
		[string]: {
			loaded: boolean,
			luaOk: boolean,
			exports: {[string]: any}?,
			thread: thread?,
			luaErr: string?
		}
	},

	entry: (ImportContext) -> {[string]: any},
	require: (ImportContext, path: string) -> {[string]: any}
}

local IMPORT_CONTEXTS: {[HWI]: ImportContext} = {}
local UNRESOLVED_DEPENDENCY_IDENTIFIERS: {[string]: {[string]: ImportContext}} = {}
local blockedHWI -- used to stop the HWI itself being included in the exports

local function DO_IMPORT(ctx: ImportContext, obj)
	-- this needs to spawn an "import" with knowledge of the relative path
	-- and package


end

local function resolveDependencies(packageObj, context)
	
end	

function exports.fromHWI(packageObj): ImportContext
	local context = {} :: ImportContext
	context.package = packageObj
	context.lazyDependencies = {}
	context.entrymod = packageObj.config.entry
	context.modules = {} -- these are lazy resolved
	
	function context:require(path)
		local obj = self.package.objects[`/source{path}`]
		if not obj then error(`module {path} is not in the package`) end
		return DO_IMPORT(self, obj)
	end

	IMPORT_CONTEXTS[packageObj] = context
	local obj = packageObj.objects[context.entrymod]
	if not obj then error("cant find a defined entrypoint for the package") end
	local exports = DO_IMPORT(context, obj)

	if exports.main then
		-- runtime object
		-- blocks external dependency resolution
		context.isRunnable = true
	end
	resolveDependencies(packageObj, context)

	return context
end

return exports