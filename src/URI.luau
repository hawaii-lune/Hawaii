-- Implements a UNIX-like URI
-- Can output to a Windows-like or UNIX-like path

local process = require("@lune/process")
local env = process.env
type PathOutputTarget = "UNIX"|"DOS"
local staticPaths = setmetatable({}, {__mode = "v"})

local LOCAL_TARGET = if process.os == "windows" then "DOS" else "UNIX"
local ILLEGAL_DOS_CHARS = '[:<>"|?*\\/]'
local DOS_DRIVE = "^%w+:$"

export type URI = typeof(setmetatable({}::{
	Ancestors: {string},
	File: string,
	Relative: boolean,
	Parent: (URI) -> URI?,
	ToString: (URI, target: PathOutputTarget?) -> string
},{}::{
	__index: (URI, string) -> URI?
}))

local function getStaticIndex(components: {string}, file: string?, relative: boolean, preserveCasing: boolean)
	local parentString = table.concat(components, "/")
	local path = if file then `{parentString}/{file}` else parentString
	local out = if relative then path else `/{path}`
	return if preserveCasing then out else string.lower(out)
end

local newURI

local function appendURI(uri: URI, loc: string): URI?
	if string.find(loc, "/", 0, true) then error("illegal seperator / in path") end

	if loc == "." then return uri end
	local ancestry = table.clone(uri.Ancestors)

	if loc ~= ".." then
		table.insert(ancestry, uri.File)
		table.insert(ancestry, loc)
	else
		if not ancestry[1] then return nil end
	end

	return newURI(ancestry, uri.Relative)
end

local function URIParent(self: URI): URI?
	return appendURI(self, "..")
end

local function DOSToString(uri: URI): string
	-- this should validate that if relative = false, the first object matches
	-- the drive format, and everything else is allowed in path rules

	-- technically we should restrict the prohibited file names here but this
	-- is legacy jank that i'd rather not
	local parts = table.clone(uri.Ancestors)
	table.insert(parts, uri.File)

	for index, part in parts do
		if index == 1 and not uri.Relative then
			-- first part should match drive format
			if not string.match(part, DOS_DRIVE) then error("malformed drive letter") end
			continue
		end

		-- each component should not conflict with the prohibited chars
		if string.match(part, ILLEGAL_DOS_CHARS) then error("prohibited DOS character in path") end
	end

	return table.concat(parts, "\\")
end
	
local function URIToString(self: URI, target: string?): string
	target = target or LOCAL_TARGET
	-- because DOS paths are more restrictive, it needs its own function
	if target == "DOS" then return DOSToString(self) end 

	local UNIX_REL = if self.Relative then "" else "/"
	return if self.Ancestors[1] then `{UNIX_REL}{table.concat(self.Ancestors, "/")}/{self.File}` else `{UNIX_REL}{self.File}` 
end

local function stringTrim(str: string): string
	return string.match(str, "^%s*(.-)%s*$") or ""
end

local URI_MT = {
	__index = appendURI,
}

function newURI(components: {string}, relative: boolean, source: PathOutputTarget): URI
	local staticIndex = getStaticIndex(components, nil, relative, source == "UNIX")
	local uri = staticPaths[staticIndex]

	if not uri then
		local file = table.remove(components, #components)

		uri = setmetatable({
			Ancestors = components,
			File = file,
			Relative = relative,
			Parent = URIParent,
			ToString = URIToString
		}, URI_MT)

		table.freeze(uri)
		staticPaths[staticIndex] = uri
	end

	return uri::URI
end

local URI = {}

local function sanitisePathComponents(path: string, joiner: "\\"|"/"): ({string}, boolean)
	-- removes leading and trailing joiner, returns if relative
	if stringTrim(path) == "" then error("The path is empty.") end
	local components = string.split(path, joiner)

	if string.sub(path, -1) == joiner then
		table.remove(components, #components)
	end

	local relative = stringTrim(components[1]) ~= ""
	if not relative then table.remove(components, 1) end

	for index, component in components do
		components[index] = stringTrim(component)
	end

	return components, relative
end

function URI.fromUNIX(path: string): URI
	local components, relative = sanitisePathComponents(path, "/")
	return newURI(components, relative, "UNIX")
end

function URI.fromDOS(path: string): URI
	path = string.gsub(path, "/", "\\")
	local components, relative = sanitisePathComponents(path, "\\")

	if not relative then
		local upper = string.match(process.cwd, "^(%w+:)\\")
		table.insert(components, 1, if LOCAL_TARGET == "UNIX" then "C:" else string.upper(upper))
	end

	for index, component in components do
		local trimmed = stringTrim(component)
		if index == 1 and string.match(trimmed, DOS_DRIVE) then
			-- if "" then assume its \, in this case, we should retrieve the CWD and pull the drive letter
			if relative then
				relative = false
				components[1] = string.upper(trimmed)
			end
			continue
		end

		if string.match(trimmed, ILLEGAL_DOS_CHARS) then error(`File {trimmed} contains an illegal DOS character`) end
		components[index] = trimmed
	end

	return newURI(components, relative, "DOS")
end

function URI.new(path: string): URI
	return if LOCAL_TARGET == "DOS" then URI.fromDOS(path) else URI.fromUNIX(path)
end

return URI