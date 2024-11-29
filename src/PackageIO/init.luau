local Types = require("./Types")

export type CHWIPackage = Types.CHWIPackage
export type HWIObject = Types.HWIObject
export type HWIPackage = Types.HWIPackage
export type HWIPackageStream = Types.HWIPackageStream

return {
	HWIReader = require("./HWIReader"),
	CHWIReader = require("./CHWIReader"),
	HWIWriter = require("./HWIWriter"),
	CHWIWriter = require("./CHWIWriter")
}