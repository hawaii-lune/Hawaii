--CHWIReader
export type HWIPackageStream = {
	name: string,
	content: buffer,
	loadedPackage: HWIPackage?,
	Open: (HWIPackageStream) -> HWIPackage
} 

export type CHWIPackage = {
	name: string,
	entry: HWIPackage, -- entry package is loaded into context
	packages: {[string]: HWIPackageStream}
}

-- CHWIWriter
-- This is just a function so no function is needed
--HWIReader
export type HWIObject = {
	compressed: boolean,
	filePath: string?,
	content: buffer,
	Open: (HWIObject) -> buffer
}

export type HWIConfig = {
	--this should be json permitted objects

	entry: string?,
	compiled: boolean,
	compressed: boolean,
	native: boolean,
	dependencies: {[string]: string}
}

export type HWIPackage = {
	objects: {[string]: HWIObject},
	name: string,
	config: HWIConfig,
}

-- HWIWriter
export type ObjectType = "source"|"object"

export type HWIWriter = {
	name: string,
	config: HWIConfig,
	objects: {[string]: buffer},
	AddObject: (HWIWriter, ObjectType, path: string, stream: buffer) -> (),
	AttachPrebuiltHWI: (HWIWriter, prebuilt: buffer) -> (),
	SetEntryPath: (HWIWriter, path: string) -> (),
	ToBuffer: (HWIWriter) -> buffer,
	content: buffer?,
} 

return nil