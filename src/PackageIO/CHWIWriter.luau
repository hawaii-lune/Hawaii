-- handles writing CHWI files
-- provide a list of HWI files and the entry point
local BasicTypes = require("./BasicTypes")
local VersionConfig = require("./VersionConfig")
local serde = require("@lune/serde")
local Types = require("./Types")

local function allocateWriterBuffer(pkgName, entryName, sizeStreams, contentSizes: {number}, sumOffset: number?)
	-- computes the size to allocate, then we can just write data to it
	local pkl, enl = string.len(pkgName), string.len(entryName)

	local sum = (sumOffset or 0)
		+ BasicTypes.ULEB128Size(pkl) + pkl
		+ BasicTypes.ULEB128Size(enl) + enl
		+ BasicTypes.ULEB128Size(sizeStreams)
	for _, num in contentSizes do
		sum += BasicTypes.ULEB128Size(num) + num + 1 -- the extra 1 is for a filetype identifier (not available yet)
	end

	return buffer.create(sum)
end

return function(pkgName: string, entry: Types.HWIWriter, streams: {Types.HWIWriter}): buffer
	-- parse each HWI file to a stream, then use this to validate if the entry point is a valid stream
	local sizeStreams = #streams
	local hwiFiles: {[string]: string} = {}
	local contentSizes = table.create(sizeStreams * 2)
	local entryName = entry.name
	local entryFileFound = false

	if sizeStreams == 0 then error(`No provided HWIWriters, cant parse to CHWI`) end
	for i = 1, sizeStreams do
		local stream = streams[i]

		if stream.name == entryName then entryFileFound = true end
		local source = serde.compress("zlib", stream:ToBuffer())
		contentSizes[(i*2)-1] = string.len(stream.name)
		contentSizes[i*2] = string.len(source)
		hwiFiles[stream.name] = source
	end
	if not entryFileFound then error(`entry file {entryName} not present in package streams`) end

	local writer = allocateWriterBuffer(pkgName, entryName, sizeStreams, contentSizes, 5)
	buffer.writestring(writer, 0, `CHWI`)
	buffer.writeu8(writer, 4, VersionConfig.CHWI_PREFER)
	local offsetPointer = {offset = 5}

	BasicTypes.InsertString(writer, pkgName, offsetPointer)
	BasicTypes.InsertString(writer, entryName, offsetPointer)
	BasicTypes.InsertULEB128(writer, sizeStreams, offsetPointer)
	for name, stream in hwiFiles do
		buffer.writeu8(writer, offsetPointer.offset, 0)
		offsetPointer.offset += 1
		BasicTypes.InsertString(writer, name, offsetPointer)
		BasicTypes.InsertString(writer, stream, offsetPointer)
	end

	return writer
end
