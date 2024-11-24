type HWIObject = {
	compressed: boolean,
	hash: string?,
	filePath: string?,
	content: buffer,
	Open: (HWIObject) -> buffer
}

type HWIPackage = {
	objects: {[string]: HWIObject},
	hashes: {[string]: string}?
}

--[=[
	Imports a module with a given set of imports, or `*` for the entire `exports`
	table.

	Supports one of two path types
	* `source` - uses an alias path defined in `hawaii.toml`
	* `/sources/source` - imports a file from the top of the package
	  * Relative paths are not supported yet
]=]--
declare import: (
	(string, ...string) -> {from: (string) -> any}
)

--[=[
	A table for writing the module exports, should be returned from all modules.

	This table is frozen once returned and cant be written to further.
]=]--
declare exports: {[string]: any}

--[[
	A static proxy reference to this HWI package. Only exports a frozen copy of
	the objects table, and hashes if enabled within the root package.
]]--
declare package: HWIPackage