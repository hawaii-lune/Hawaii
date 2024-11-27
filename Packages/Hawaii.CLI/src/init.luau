local Shell = import "*" .from "/source/Shell"

local CLI_VERSION = "0.1.0" -- TODO: package.version would be a useful flag here
-- this would require updating the HWI format so not now
local PROJECT_HEADER = "Luau Packaging Tool for Lune\nUsage: hawaii.exe [command]"

local function buildCommandHook(packageSource)
	local CLI_ENTRY = import "_CLI_ENTRY" .from (packageSource)
	
	return Shell.newCommand(
		CLI_ENTRY.CommandName,
		CLI_ENTRY.Summary,
		CLI_ENTRY.Options,
		CLI_ENTRY.Argument,
		CLI_ENTRY.Execute
	)
end

function exports.main(argc, argv)
	local ok = Shell.newApp(
		"hawaii",
		"Luau packaging tool based on Lune",
		CLI_VERSION,
		{
			build = buildCommandHook("@builder")
		}
	)

	-- for the first time round, we need to hardcode these options because
	-- lune cli does silly things
	if ok.Execute(table.clone(argv)) then return 0 else return 1 end
end