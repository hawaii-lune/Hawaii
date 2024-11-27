-- This is the base CLI.
-- It handles the logic for loading HWI files, and CHWI files.

-- Parts of this package, under /exports/ are extracted and included raw in
-- every Hawaii exe.
-- metatablecat 2024

-- Several libraries can create the CHWI files, but we suggest Hawaii.HWIWriter
-- which creates a HWI-compatible object.

local fs = require("@lune/fs")

local function buildDirectoryTree(filePath: string)
	local components = string.split(filePath, "/")
	local cwd = table.remove(components, 1)
	for _, component in components do
		if not fs.isDir(cwd) then fs.writeDir(cwd) end
		cwd ..= `/{component}`
	end
end

-- Copies all objects from the /exports/ folder into a new build
-- fragment, then adds the CHWI file as ".chwi.luau"

-- Because of CHWI writers may be of different formats, we need to allow a buffer write here
function exports.ExtractBootstrapper(outDir: string)
	local exportsObjectPatten = "^/objects/(.-)$"
	local linkableSourceObjects = {}
	
	for _, object in package.objects do
		local objectName = string.match(object.filePath, exportsObjectPatten)
		if objectName then
			linkableSourceObjects[objectName] = object
		end
	end

	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	for name, object in linkableSourceObjects do
		local stream = object:Open()
		buildDirectoryTree(`{outDir}/{name}`)
		fs.writeFile(`{outDir}/{name}`, stream)
	end
end

exports.Bookstrapper, exports.ImportEngine, exports.PackageIO =
	import("Bookstrapper", "ImportEngine", "PackageIO") .from("/FFI/Bootstrapper")
return exports