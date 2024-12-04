local fs = require("@lune/fs")

local function buildDirectoryTree(filePath: string)
	local components = string.split(filePath, "/")
	local cwd = table.remove(components, 1)
	for _, component in components do
		if not fs.isDir(cwd) then fs.writeDir(cwd) end
		cwd ..= `/{component}`
	end
end

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
	import("Bookstrapper", "PackageIO") .from("/FFI/Bootstrapper")
return exports