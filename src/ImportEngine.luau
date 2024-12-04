-- This implements the Import syntax when loaded by the bootstrapper
-- These are relatively low-level APIs and can break stuff if not used
-- correctly

local PackageIO = require("./PackageIO")

local ImportEngine = {}

local luau = require("@lune/luau")
type Exportable = {[string]: any}
type HWI = PackageIO.HWIPackage

type PackageContext = {
	Name: string,
	Package: HWI,
	Modules: {[string]: {
		loaded: boolean,
		export: Exportable,
		luaOk: boolean,
		luaErr: string?,
		heldThreads: {thread},
		workerThread: thread?
	}},
	LazyDependencies: {[string]: PackageContext},
	EntryExport: Exportable?
}

export type RuntimeContext = {
	Name: string,
	Packages: {
		[string]: PackageContext
	},
	EntryPackage: PackageContext,
	LoadObject: (RuntimeContext, package: PackageContext, object: string) -> Exportable,
	LoadPackage: (RuntimeContext, package: PackageContext) -> Exportable,
	LoadLibrary: (RuntimeContext) -> Exportable,
	AddPackage: (RuntimeContext, HWI, isEntry: boolean) -> (),
	BuildDependencies: (RuntimeContext) -> (),
	Run: (RuntimeContext, args: {string}) -> (),
}

local function getEntryItem(self: RuntimeContext)
	-- resolves the .entry point in the entry package context
	local entryPackage = self.EntryPackage
	if not entryPackage then error("package has no assigned entry point") end
	local package = entryPackage.Package
	return entryPackage, package.config.entry
end

local function generateRelativeImporter(self: RuntimeContext, ctx: PackageContext, object: string)
	-- generates an import for the given object
	-- this calls LoadObject relatively to the package itself

	-- "@" means it will try to find a relative alias
	return function(...: string)
		local captured = {...}
		local sizeCaptured = #captured
		if sizeCaptured < 1 then error("at least one object must be imported") end

		return {
			from = function(package)
				local exportWorker
				local init = string.sub(package,1,1)
				local rhs = string.sub(package, 2)

				if init == "@" then
					-- package reference based on alias
					local resolvedContext = ctx.LazyDependencies[string.lower(rhs)]
					if not resolvedContext then error(`Cant find package from alias {rhs}`) end

					exportWorker = self:LoadPackage(resolvedContext)

				elseif init == "/" then
					-- fixed path in package itself
					-- attach.luau to the path if it doesn't end with it
					if string.sub(package, -5) ~= ".luau" then
						package ..= ".luau"
					end

					exportWorker = self:LoadObject(ctx, package)

				else
					error(`Cant find package or module {package}`)
				end

				if captured[1] == "*" then return exportWorker end
				local output = table.create(sizeCaptured)

				for i, capture in captured do
					local export = exportWorker[capture]
					if not export then error(`Cant resolve export {capture} in object {package}`) end
					output[i] = export
				end

				return unpack(output)
			end
		}
	end
end

local function Exportable(self: RuntimeContext, package: PackageContext, object: string, table: {[string]: any}?): Exportable
	local exportable = setmetatable(table or {}, {
		__tostring = function()
			return `Module<{self.Name}:{package.Name}{object}>`
		end,
		__metatable = "The metatable of Exportable is locked"
	})

	return exportable
end

local function loadCallmangler(self: RuntimeContext, package: PackageContext, object: string)
	-- returns a callmangler
	local hwi = package.Package
	local obj = hwi.objects[object]
	if not obj then error(`could not find object {object} in package {hwi.name}`) end
	local bytecode = buffer.tostring(obj:Open())

	--TODO: release/debug switch, currently using roblox defaults
	if not hwi.config.compiled then
		bytecode = luau.compile(bytecode, {
			optimizationLevel = 1,
			coverageLevel = 0,
			debugLevel = 1
		})
	end

	local callmangler = luau.load(bytecode, {
		debugName = `/{self.Name}/{package.Name}{object}`,
		codegenEnabled = hwi.config.native
	})

	local loadfunc = callmangler()

	if type(loadfunc) ~= "function" then
		error("Build error: package does not contain a hookable function. Rebuilding your HWI usually fixes this issue.")
	end

	return loadfunc
end

local function threadWorker(
	objectState,
	callmangler,
	importFunc,
	exportable,
	package
)
	local ok, export = pcall(callmangler, importFunc, exportable, package)
	if not ok then
		objectState.luaOk = false
		objectState.luaErr = export or "No output from Lua."
	end

	objectState.loaded = true
	objectState.workerThread = nil
	for _, thread in objectState.heldThreads do
		coroutine.resume(thread)
	end
	table.clear(objectState.heldThreads)
end

function ImportEngine.newRuntimeContext(name: string): RuntimeContext
	local rtCTX = {} :: RuntimeContext
	rtCTX.Name = name
	rtCTX.Packages = {}

	function rtCTX.LoadObject(self: RuntimeContext, package: PackageContext, object: string): Exportable
		-- loads and initialises a new object
		-- first check if the object has already tried to be loaded
		local objectStateContext = package.Modules[object]

		if not objectStateContext then
			local importWorker = generateRelativeImporter(self, package, object)
			local exportable = Exportable(self, package, object)
			local callmangler = loadCallmangler(self, package, object)
			local packageExport = {
				objects = package.Package.objects
			}
	
			objectStateContext = {
				loaded = false,
				export = exportable,
				luaOk = true,
				luaErr = nil,
				heldThreads = {}
			}
	
			-- start the callmangler thread
			local thread = coroutine.create(threadWorker)
			objectStateContext.workerThread = thread
			package.Modules[object] = objectStateContext
			coroutine.resume(thread, objectStateContext, callmangler, importWorker, exportable, packageExport)
		end

		if not objectStateContext.loaded then
			table.insert(objectStateContext.heldThreads, coroutine.running())
			coroutine.yield()
		end

		if not objectStateContext.luaOk then error(objectStateContext.luaErr) end
		return objectStateContext.export
	end

	function rtCTX.LoadPackage(self: RuntimeContext, package: PackageContext): Exportable
		local entryPath = package.Package.config.entry
		local export = package.EntryExport

		if not export then
			export = self:LoadObject(package, entryPath)
			export.EntryExport = export
		end

		return export
	end

	function rtCTX.LoadLibrary(self: RuntimeContext): Exportable
		local entryPackage = self.EntryPackage
		if not entryPackage then error("Package does not have an entry point") end
		return self:LoadPackage(entryPackage)
	end

	function rtCTX.Run(self: RuntimeContext, args: {string})
		local runtimePackage, runtimePath = getEntryItem(self)
		local export = self:LoadObject(runtimePackage, runtimePath)
		if not export.main then error("Cant load runtime package because its export does not have a main function") end
		
		local code = export.main(#args, args)
		if not code or type(code) ~= "number" then code = 0 end
		return code
	end

	function rtCTX.AddPackage(self: RuntimeContext, packageObject: HWI, isEntry: boolean)
		local packageEntry = {} :: PackageContext
		packageEntry.Name = packageObject.name
		packageEntry.Package = packageObject
		packageEntry.Modules = {}
		packageEntry.LazyDependencies = {}
		packageEntry.EntryExport = nil

		self.Packages[packageObject.name] = packageEntry
		if isEntry then self.EntryPackage = packageEntry end
	end

	function rtCTX.BuildDependencies(self: RuntimeContext)
		for package, context in self.Packages do
			for alias, packageID in context.Package.config.dependencies do
				local pkgRef = self.Packages[packageID]
				if not pkgRef then error(`could not load package {packageID} for {package}`) end
				context.LazyDependencies[string.lower(alias)] = pkgRef
			end
		end
	end

	return rtCTX
end

function ImportEngine.fromCHWI(chwi: PackageIO.CHWIPackage): RuntimeContext
	local rtCTX: RuntimeContext = ImportEngine.newRuntimeContext(chwi.name)

	for _, packageStream in chwi.packages do
		local object = packageStream:Open()
		rtCTX:AddPackage(object, object == chwi.entry)
	end
	rtCTX:BuildDependencies()

	return rtCTX
end

-- Mainly an internal layer for /FFI:Bootstrapper/ in the System package, this bypasses the file io check
-- and just loads it
function ImportEngine.setExport(context: RuntimeContext, packageContext: PackageContext, object: string, exportTable)
	local exp = Exportable(context, packageContext, object, exportTable)

	packageContext.Modules[object] = {
		loaded = true,
		export = exp,
		luaOk = true,
		luaErr = nil,
		heldThreads = {}
	}
end

return ImportEngine