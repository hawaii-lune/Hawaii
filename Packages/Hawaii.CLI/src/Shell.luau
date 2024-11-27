-- Handles shell input

-- ANSI-like funcs
local function awarn(msg: string)
	print(`\27[1m\27[41m{msg}\27[40m\27[22m, showing help...`)
end

local function awarn2(msg: string, rhs: string)
	print(`\27[1m\27[41m{msg}:\27[40m\27[22m \27[31m{rhs}\27[37m`)
end

type ParsedArgumentTable = {
	Options: {[string]: boolean|string},
	Arguments: {string}
}

type CommandOption = {
	Description: string,
} & ({
	ArgumentOptional: boolean,
	ArgumentShorthand: string,
	ArgValidate: ((string) -> (boolean, string?))?
} | {})

type CommandOptionDenested = {
	BaseOption: CommandOption,
	Key: string, -- chooses the first alias in the list
}

type ShellCommand = {
	CommandName: string,
	Summary: string,

	Argument: {
		Shorthand: string,
		Description: string,
		Optional: boolean,
		ArgValidate: (({string}) -> (boolean, string?))?
	}?,

	CommandOptions: {[{string}]: CommandOption}?,
	DenestedOptions: {[string]: CommandOptionDenested}?,

	Execute: (ParsedArgumentTable) -> boolean
}

local helpCommandKey = {"h", "help"}

local function wrapOptionWidth(c: string): string
	return `{string.len(c) == 1 and "-" or "--"}{c}`
end

local function findHelperInArgs(args: {string})
	for _, arg in args do
		if arg == "-h" or arg == "--help" then return true end
	end
	return false
end

function exports.newCommand(
	commandName: string,
	summary: string,
	options: {[{string}]: CommandOption}?,
	argument: {
		Description: string,
		ArgValidate: (({string}) -> boolean)?
	}?,
	exec: (ParsedArgumentTable) -> boolean
): ShellCommand

	local denested: {[string]: CommandOptionDenested}
	if options then
		denested = {}
		if not options[helpCommandKey] then
			options[helpCommandKey] = {
				Description = "Shows help information for command",
			}
		end

		for tags, option in options do
			local alias = tags[1]
			for _, key in tags do
				denested[wrapOptionWidth(key)] = {
					BaseOption = option,
					Key = alias
				}
			end
		end
	end

	local command = {
		CommandName = commandName,
		Summary = summary,
		Argument = argument,
		CommandOptions = options,
		DenestedOptions = denested,
		Execute = exec
	}

	table.freeze(command)
	return command
end

local function getLargestKeyString(strings: {[string]: string}): number
	local largest = 0
	for str in strings do
		local noAnsi = string.gsub(str, "\27%[%d+m", "")
		largest = math.max(largest, string.len(noAnsi))
	end

	return largest
end

local function listifyAndSort(kv: {[string]: string}): {{key: string, value: string}}
	local list = {}

	for key, value in kv do
		table.insert(list, {
			key = key,
			value = value
		})
	end

	table.sort(list, function(a, b)
		if a.key == b.key then
			return a.value < b.value
		else
			return a.key < b.key
		end
	end)

	return list
end

local function getFormattedKVPair(kv: {[string]:string}): string
	local size = getLargestKeyString(kv)
	local sorted = listifyAndSort(kv)
	local stream = {}

	for _, message in sorted do
		local noAnsi = string.gsub(message.key, "\27%[%d+m", "")
		local paddingSize = 2 + (size - string.len(noAnsi))
		table.insert(stream, `{message.key}{string.rep(" ", paddingSize)}{message.value}`)
	end

	return table.concat(stream, "\n  ")
end

local function SHOW_HELP_INFO(command: ShellCommand, shellExec: ShellCommand, commands: {[string]: ShellCommand}?)
	local messageBuffer = {command.Summary}

	-- generate usage message
	local usage = {`\27[1m\27[4mUsage:\27[22m\27[24m\n  \27[33m{shellExec.CommandName}\27[37m`}
	if command ~= shellExec then
		table.insert(usage, `\27[33m{command.CommandName}\27[37m`)
	end

	if command.CommandOptions and next(command.CommandOptions) then
		table.insert(usage, "\27[35m[OPTIONS]\27[37m")
	end

	local argument = command.Argument
	local argumentControl
	if argument then
		if argument.Optional then
			if command == shellExec then
				argumentControl = `\27[33m[{string.upper(argument.Shorthand)}]\27[37m`
			else
				argumentControl = `\27[36m[{string.upper(argument.Shorthand)}]\27[37m`
			end
		else
			argumentControl = `\27[32m<{string.upper(argument.Shorthand)}>\27[37m`
		end

		table.insert(usage, argumentControl)
	end

	table.insert(messageBuffer, table.concat(usage, " "))
	-- generate options and arguments


	if commands then
		-- mode: show commands
		local commandKVPair = {}
		for name, exec in commands do
			commandKVPair[`\27[33m{name}\27[37m`] = exec.Summary
		end
		table.insert(messageBuffer, `\27[1m\27[4mCommands:\27[22m\27[24m\n  {getFormattedKVPair(commandKVPair)}`)
	else
		-- mode: show argument
		table.insert(messageBuffer, `\27[1m\27[4mArguments:\27[22m\27[24m\n  {argumentControl}  {argument.Description}`)
	end

	-- show options
	if command.CommandOptions then
		local optionKVPair = {}
		for optionPairs, exec in command.CommandOptions do
			local processed = {}
			for _, option in optionPairs do
				table.insert(processed, wrapOptionWidth(option))
			end

			if exec.ArgumentShorthand then
				local arg
				if exec.ArgumentOptional then
					arg = `\27[36m[{string.upper(exec.ArgumentShorthand)}]\27[37m`
				else
					arg = `\27[32m<{string.upper(exec.ArgumentShorthand)}>\27[37m`
				end

				optionKVPair[`\27[35m{table.concat(processed, ", ")}\27[37m {arg}`] = exec.Description
			else
				optionKVPair[`\27[35m{table.concat(processed, ", ")}\27[37m`] = exec.Description
			end
		end
		table.insert(messageBuffer, `\27[1m\27[4mOptions:\27[22m\27[24m\n  {getFormattedKVPair(optionKVPair)}`)
	end

	print(table.concat(messageBuffer, "\n\n"))
end

function exports.newApp(
	commandName: string,
	summary: string,
	shellVersion: string,
	commands: {[string]:ShellCommand}
): ShellCommand
	-- generates a static shell command for the app to use

	local argument = {
		Shorthand = "COMMAND",
		Description = "Command to execute",
		Optional = true
	}

	local options = {
		[helpCommandKey] = {
			Description = "Shows help information",
			ArgumentOptional = true,
			ArgumentShorthand = "COMMAND"
		},

		[{"v", "version"}] = {
			Description = "Shows package version."
		}
	}

	local shellExec; shellExec = exports.newCommand(commandName, summary, options, argument, function(args: {string})
		if #args == 0 then
			SHOW_HELP_INFO(shellExec, shellExec, commands)
			return true
		end

		local command = table.remove(args, 1)
		local isSwitch = string.sub(command, 1, 1) == "-"
		
		if isSwitch then
			if command == "-v" or command == "--version" then
				print(shellVersion)
				return true
			end

			if command ~= "-h" and command ~= "--help" then
				awarn(`Invalid option {command}`)
			else
				local commandLockInOption = args[1]
				local helping = commands[commandLockInOption]
				if commandLockInOption and helping then
					SHOW_HELP_INFO(helping, shellExec)
					return true
				end
			end
			-- show help info for root command
			
			SHOW_HELP_INFO(shellExec, shellExec, commands)
		else
			local exec = commands[command]

			if not exec then
				awarn(`Command {command} not available`)
				SHOW_HELP_INFO(shellExec, shellExec, commands)

				return false
			end

			if findHelperInArgs(args) then
				SHOW_HELP_INFO(exec, shellExec)
				return true
			end

			-- begin arg validating
			local argTable: ParsedArgumentTable = {
				Options = {},
				Arguments = {}
			}

			local focusOption: CommandOptionDenested? = nil
			local lastArg: string?

			for _, arg in args do
				local isSwitch = string.sub(arg, 1, 1) == "-"

				if focusOption then
					local baseOptionCommand = focusOption.BaseOption
					-- focus option, should run arg validate if needed
					if baseOptionCommand.ArgumentShorthand then
						-- peeks option
						if not baseOptionCommand.Optional and isSwitch then
							awarn(`Invalid argument {arg} to option {lastArg or "ERROR"}`)
							SHOW_HELP_INFO(exec, shellExec)
							return false
						end

						if not isSwitch then -- process argument
							local validator = baseOptionCommand.ArgValidator
							if validator then
								local validated, msg = validator(arg)
								if not validated then
									if msg then
										awarn2(`Argument validation for option {lastArg} failed`, msg)
									else
										awarn(`Argument validation for option {lastArg} failed`)
										SHOW_HELP_INFO(exec, shellExec)
									end

									return false
								end
							end

							argTable.Options[focusOption.Key] = arg
							focusOption = nil
							continue
						end

						-- set to true and allow fallthrough
						argTable.Options[focusOption.Key] = true
						focusOption = nil
					end
				end

				if isSwitch then
					-- try to focus down the command or throw if unknown
					focusOption = exec.DenestedOptions[arg]

					if argTable.Options[focusOption.Key] then
						awarn(`Option {arg} already defined`)
						SHOW_HELP_INFO(exec, shellExec)
						return false
					end

					if not focusOption then
						awarn(`Invalid option {arg}`)
						SHOW_HELP_INFO(exec, shellExec)
						return false
					end

					lastArg = arg
					continue
				end

				local argument = exec.Argument
				if argument then
					-- validation is done on the second step for  arguments
					table.insert(argTable.Arguments, arg)
				else
					awarn(`Invalid argument {arg}`)
					SHOW_HELP_INFO(exec, shellExec)
					return false
				end
			end

			if focusOption then
				if focusOption.BaseOption.ArgumentShorthand and not focusOption.BaseOption.ArgumentOptional then
					awarn(`Option {lastArg} requires an argument.`)
					SHOW_HELP_INFO(exec, shellExec)
					return false
				end

				argTable.Options[focusOption.Key] = true
			end

			-- validate arguments
			local argument = exec.Argument
			if not argument.Optional and not argTable.Arguments[1] then
				awarn(`At least one argument is required for this command`)
				SHOW_HELP_INFO(exec, shellExec)
				return false
			end

			local validator = argument and argument.ArgValidate
			if validator then
				local validated, msg = validator(argTable.Arguments)
				if not validated then
					if msg then
						awarn2(`Argument validation failed`, msg)
					else
						awarn(`Argument validation failed`)
						SHOW_HELP_INFO(exec, shellExec)
					end

					return false
				end
			end

			return exec.Execute(argTable)
		end

		return true
	end)

	return shellExec
end
