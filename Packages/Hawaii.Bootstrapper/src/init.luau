-- This is the base CLI.
-- It handles the logic for loading HWI files, and CHWI files.

-- Parts of this package, under /exports/ are extracted and included raw in
-- every Hawaii exe.
-- metatablecat 2024

-- Several libraries can create the CHWI files, but we suggest Hawaii.HWIWriter
-- which creates a HWI-compatible object.

local fs = require("@lune/fs") -- TODO: lune std bindings, this is an evil hack

-- Copies all objects from the /exports/ folder into a new build
-- fragment, then adds the CHWI file as ".chwi.luau"

-- Because of CHWI writers may be of different formats, we need to allow a buffer write here
function exports.CreateBuildFragment(outDir: string, runtimeHWI: buffer, chwi: buffer)
	local exportsObjectPatten = "^/objects/(.-)$"
	local linkableSourceObjects = {}
	
	for _, object in package.objects do
		local objectName = string.match(object.Name, exportsObjectPatten)
		if objectName then
			linkableSourceObjects[objectName] = object
		end
	end

	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	for name, object in linkableSourceObjects do
		local stream = object:Read()
		fs.writeFile(`{outDir}/{stream}`, buffer.tostring(stream))
	end

	fs.writeFile(`{outDir}/core.hwi.luau`, buffer.tostring(runtimeHWI))
	fs.writeFile(`{outDir}/.chwi.luau`, buffer.tostring(chwi))
end

return exports