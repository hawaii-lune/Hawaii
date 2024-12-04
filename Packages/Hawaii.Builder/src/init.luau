-- Hawaii.Builder
-- technically a runtime component but detatched for ease of use externally

local PackageIO = import ("PackageIO") .from "@system"
local ExtractBootstrapper = import "ExtractBootstrapper" .from "/source/BootstrapperBuilder"
local Base64 = import "*" .from "/source/Base64"
local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

type DirectoryTree = {{path: string, content: string}}

local function buildDirectoryTree(dir, cwd, attach): DirectoryTree
	attach = attach or {}
	cwd = cwd or ""

	for _, file in fs.readDir(dir) do
		local append = if cwd ~= "" then "/" else ""

		if fs.isDir(`{dir}/{file}`) then
			buildDirectoryTree(`{dir}/{file}`, `{cwd}{append}{file}`, attach)
		else
			table.insert(attach, {
				path = `{cwd}{append}{file}`,
				content = fs.readFile(`{dir}/{file}`)
			})
		end
	end

	return attach
end

type Depdendency = {
	dependencies: {
		[string]: {
			path: string
		}
	}?,

	directories: {
		objects: string?,
		source: string,
	},

	build: {
		compiled: boolean?,
		compressed: boolean?,
		native: boolean?
	}?,

	entry: string?,
	location: string,
	name: string,
	resolvedDependencies: {
		{
			alias: string,
			obj: string
		}
	}
}

local function buildDependencyTree(buildchain: {[string]: Depdendency}, packageFolder: string)
	if not fs.isFile(`{packageFolder}/hawaii.toml`) then
		error(`cant hawaii.toml config file in object {packageFolder}`)
	end

	local config = serde.decode("toml", fs.readFile(`{packageFolder}/hawaii.toml`))
	config.resolvedDependencies = {}
	config.location = packageFolder
	
	buildchain[config.name] = config
	if config.dependencies then
		for k, v in config.dependencies do
			-- resolve child dependencies
			local actualPackageName = buildDependencyTree(buildchain, `{packageFolder}/{v.path}`)
			table.insert(config.resolvedDependencies, {alias = k, obj = actualPackageName})
		end
	end
		
	return config.name
end

local COLUMN_SIZE = 80
local function writeBin(stream, filePath)
	stream = Base64.encode(stream)
	local size = buffer.len(stream)
	local lines = math.ceil(size / COLUMN_SIZE)
	local sections = table.create(lines)

	for i = 1, lines do
		local lowBound = (i-1) * COLUMN_SIZE
		local highBound = math.min(size, i * COLUMN_SIZE)

		sections[i] = buffer.readstring(stream, lowBound, highBound - lowBound)
	end

	fs.writeFile(filePath, `return ([[\n{table.concat(sections, "\n")}\n]])`)
end

local function buildProcess(
	dir,
	darkluaEntry,
	target,
	chwiName
)
	process.spawn("darklua", {"process", `{dir}/{darkluaEntry}`, `{dir}/out/BUNDLE.luau`}, {
		stdio = "inherit"
	})

	process.spawn("lune", {
		"build",
		"-t",
		target,
		"-o",
		`{dir}/out/{chwiName}.exe`,
		`{dir}/out/BUNDLE.luau`
	}, {
		stdio = "inherit"
	})
end

function exports.Build(
	inputDir: string,
	outputDir: string,
	procgenTargets: {string}?,
	chwiTarget: string?,
	bootstrapped: boolean
)

	local buildchain = {}
	local hwiFiles = {}
	local entry = buildDependencyTree(buildchain, inputDir)
	local entryResolve

	for package, dependency in buildchain do
		local writer = PackageIO.HWIWriter(package)

		local buildOptions = dependency.build
		if buildOptions then
			writer.config.compressed = if buildOptions.compressed ~= nil then buildOptions.compressed else true
			writer.config.compiled = if buildOptions.compiled ~= nil then buildOptions.compiled else true
			writer.config.native = if buildOptions.native ~= nil then buildOptions.native else false
		else
			writer.config.compressed = true
			writer.config.compiled = true
			writer.config.native = false
		end

		-- write dependencies
		local dependencies = dependency.resolvedDependencies
		if dependencies then
			for _, resolved in dependencies do
				writer.config.dependencies[resolved.alias] = resolved.obj
			end
		end
		
		-- mount source files into package, then mount object if needed
		local sourceObjects = buildDirectoryTree(`{dependency.location}/{dependency.directories.source}`)
		for _, file in sourceObjects do
			writer:AddObject("source", file.path, buffer.fromstring(file.content))
		end


		local objectDir = dependency.directories.objects
		if objectDir then
			local objects = buildDirectoryTree(`{dependency.location}/{objectDir}`)
			for _, file in objects do
				writer:AddObject("object", file.path, buffer.fromstring(file.content))
			end
		end

		writer:SetEntryPath(dependency.entry or "init.luau")
		if package == entry then
			entryResolve = writer
		end
		table.insert(hwiFiles, writer)
	end

	if not entryResolve then
		error("Could not resolve entry package")
	end

	if bootstrapped then
		ExtractBootstrapper(outputDir)
	elseif not fs.isDir(outputDir) then
		fs.writeDir(outputDir)
	end

	-- write hwi files
	for _, writer in hwiFiles do
		fs.writeFile(`{outputDir}/{writer.name}.hwi`, writer:ToBuffer())
	end

	if chwiTarget then
		local CHWIWriter = PackageIO.CHWIWriter(
			chwiTarget,
			entryResolve,
			hwiFiles
		)

		fs.writeFile(`{outputDir}/{chwiTarget}.chwi`, CHWIWriter)
		if bootstrapped then
			-- attach .chwi.luau file
			writeBin(CHWIWriter, `{outputDir}/.chwi.luau`)
		end
	end

	if procgenTargets then
		warn("Procgen is unstable, use with caution")
		buildProcess(outputDir, "init.luau", procgenTargets, chwiTarget)
	end
end

exports._CLI_ENTRY = {
	CommandName = "build",
	Summary = "Builds package folders",

	Argument = {
		Shorthand = "INPUT_DIR",
		Description = "Input directory, only the first object is built.",
		Optional = false,

		ArgValidate = function(arguments)
			if #arguments > 1 then
				return false, "only one input directory may be used"
			end

			return true
		end
	},

	Options = {
		[{"c", "chwi"}] = {
			Description = "Builds CHWI object instead of HWI objects, with INPUT_DIR as the entry point",
			ArgumentOptional = false,
			ArgumentShorthand = "CHWI_NAME"
		}
		,

		[{"o", "output"}] = {
			Description = "Sets output directory",
			ArgumentOptional = false,
			ArgumentShorthand = "OUTPUT_DIR"
		},

		[{"b", "bootstrapper"}] = {
			Description = "Build with Bootstrapper files. Allows custom bootstrapper source passing.",
			ArgumentOptional = true,
			ArgumentShorthand = "BOOTSTRAPPER"
		},

		[{"p", "procgen"}] = {
			Description = "Enables native process generation, either uses target, or native system. PROCGEN automatically enables -b and -c flags.",
			ArgumentOptional = true,
			ArgumentShorthand = "TARGET"
		}
	},
	
	Execute = function(argTable)
		local options = argTable.Options

		local inputDir = argTable.Arguments[1]
		local outputDir = options.o or "build"
		local procgen = options.p ~= nil

		local  bootstrap
		if procgen then
			if type(procgen) == "boolean" then
				procgen = `{process.os}-{process.arch}`
			end

			bootstrap = true

			-- this is dead code and never runs but needs to be here anyway
			if options.b == false then print("bootstrapper option -b is ignored because procgen is true") end
			if not options.c then
				error("CHWI option flag required for PROCGEN")
			end
		else
			bootstrap = if options.b ~= nil then options.b else false
		end

		return exports.Build(inputDir, outputDir, procgen, options.c, bootstrap)
	end
}