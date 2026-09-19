--!strict
local FileSystem = require("@lune/fs")
local Roblox = require("@lune/roblox")
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")

type IgnoreRule = {
	Raw: string,
	IsNegated: boolean,
	IsDirOnly: boolean,
	HasSlash: boolean,
	Pattern: string
}

local function PrintHelp()
	print([==[
Usage:
    lune run extract.luau [place_file.rbxl] [output_dir] [options]

Arguments:
    place_file.rbxl         Path to the Roblox place file (defaults to finding .rbxl in current directory)
    output_dir              Custom output directory (defaults to "output/<place_name>")

Options:
    --direct                Output directly into "output/" instead of "output/<place_name>/"
    --rojo-ext              Use Rojo script naming (.server.luau, .client.luau, .luau)
    --ignore-file <path>    Specify a custom ignore file (defaults to looking for ".robignore")
    -h, --help              Show this help message

Examples:
    lune run extract.luau test.rbxl
    lune run extract.luau test.rbxl output
    lune run extract.luau test.rbxl --direct
    lune run extract.luau test.rbxl --ignore-file .robignore
]==])
end

-- Extract base place name from file path
local function GetFileStem(FilePath: string): string
	local Normalized = string.gsub(FilePath, "\\", "/")
	local FileName = string.match(Normalized, "[^/]+$") or Normalized
	local Stem = string.gsub(FileName, "%.rbxlx?$", "")
	return Stem
end

-- Helper to sanitize directory/file names for Windows and Unix filesystems
local function SanitizeName(Name: string): string
	local Sanitized = string.gsub(Name, "[<>:\"/\\|?*\x00-\x1f]", "_")
	Sanitized = string.gsub(Sanitized, "[%.%s]+$", "")
	if (#Sanitized == 0) then Sanitized = "_unnamed" end

	local Upper = string.upper(Sanitized)
	local Reserved: {[string]: boolean} = {
		CON = true,
		PRN = true,
		AUX = true,
		NUL = true,
		COM1 = true,
		COM2 = true,
		COM3 = true,
		COM4 = true,
		COM5 = true,
		COM6 = true,
		COM7 = true,
		COM8 = true,
		COM9 = true,
		LPT1 = true,
		LPT2 = true,
		LPT3 = true,
		LPT4 = true,
		LPT5 = true,
		LPT6 = true,
		LPT7 = true,
		LPT8 = true,
		LPT9 = true
	}
	if (Reserved[Upper]) then Sanitized ..= "_" end
	return Sanitized
end

local function GlobToPattern(Glob: string): string
	local Pattern = string.gsub(Glob, "([%%%^%$%(%)%%.%[%]%+%-])", "%%%1")
	Pattern = string.gsub(Pattern, "%*", ".*")
	Pattern = string.gsub(Pattern, "%?", ".")
	return "^" .. Pattern .. "$"
end

local function LoadRobIgnore(FilePath: string): {IgnoreRule}
	local Rules: {IgnoreRule} = {}
	if (not FileSystem.isFile(FilePath)) then return Rules end

	local Content = FileSystem.readFile(FilePath)
	for Line in string.gmatch(Content, "[^\r\n]+") do
		Line = string.gsub(Line, "^%s+", "")
		Line = string.gsub(Line, "%s+$", "")
		if (#Line == 0 or string.sub(Line, 1, 1) == "#") then continue end

		local IsNegated = false
		if (string.sub(Line, 1, 1) == "!") then
			IsNegated = true
			Line = string.sub(Line, 2)
		end
		local IsDirOnly = false
		if (string.sub(Line, -1) == "/") then
			IsDirOnly = true
			Line = string.sub(Line, 1, -2)
		end
		local HasSlash = string.find(Line, "/") ~= nil
		local RegexPattern = GlobToPattern(Line)
		table.insert(Rules, {
			Raw = Line,
			IsNegated = IsNegated,
			IsDirOnly = IsDirOnly,
			HasSlash = HasSlash,
			Pattern = RegexPattern
		})
	end
	return Rules
end

local function ShouldIgnore(AncestorNames: {string}, ScriptName: string, Rules: {IgnoreRule}): (boolean, string?)
	if (#Rules == 0) then return false, nil end

	local FullDirectoryPath = table.concat(AncestorNames, "/")
	local FullPath = if (#FullDirectoryPath > 0) then FullDirectoryPath .. "/" .. ScriptName else ScriptName
	local FullPathWithExt = FullPath .. ".luau"
	local ImmediateParent = AncestorNames[#AncestorNames] or ""

	local Ignored = false
	local MatchedRule: string? = nil

	for _, Rule in ipairs(Rules) do
		local Matched = false
		if (Rule.HasSlash) then
			if (string.match(FullPath, Rule.Pattern)
				or string.match(FullPathWithExt, Rule.Pattern)
				or string.match(FullDirectoryPath, Rule.Pattern)
				or string.find(FullPath, Rule.Raw, 1, true)
				or string.find(FullDirectoryPath, Rule.Raw, 1, true)) then
				Matched = true
			end
		else
			if (string.match(ImmediateParent, Rule.Pattern) or ImmediateParent == Rule.Raw) then
				Matched = true
			else
				for _, AncestorName in pairs(AncestorNames) do
					if (string.match(AncestorName, Rule.Pattern) or AncestorName == Rule.Raw) then
						Matched = true
						break
					end
				end
			end
			if (not Matched and not Rule.IsDirOnly) then
				if (string.match(ScriptName, Rule.Pattern)
					or string.match(ScriptName .. ".luau", Rule.Pattern)
					or ScriptName == Rule.Raw) then
					Matched = true
				end
			end
		end

		if (Matched) then
			Ignored = not Rule.IsNegated
			MatchedRule = Rule.Raw
		end
	end

	return Ignored, MatchedRule
end

-- Parse CLI arguments
local PlaceFilePath: string? = nil
local CustomOutputDirectory: string? = nil
local CustomIgnoreFile: string? = nil
local UseDirectOutput: boolean = false
local UseRojoExtensions: boolean = false

local RawArguments: {string} = {}
for _, Argument in ipairs(Process.args) do
	if (Argument ~= "--") then table.insert(RawArguments, Argument) end
end

local ArgumentIndex = 1
while (ArgumentIndex <= #RawArguments) do
	local Argument = RawArguments[ArgumentIndex]
	if (Argument == "-h" or Argument == "--help") then
		PrintHelp()
		Process.exit(0)
	elseif (Argument == "--direct") then
		UseDirectOutput = true
	elseif (Argument == "--rojo-ext") then
		UseRojoExtensions = true
	elseif (Argument == "--ignore-file") then
		ArgumentIndex += 1
		CustomIgnoreFile = RawArguments[ArgumentIndex]
		if (not CustomIgnoreFile) then
			Stdio.ewrite("Error: --ignore-file requires a file path argument.\n")
			Process.exit(1)
		end
	elseif (string.sub(Argument, 1, 1) == "-") then
		Stdio.ewrite(`Unknown option: {Argument}\n`)
		PrintHelp()
		Process.exit(1)
	elseif (PlaceFilePath == nil) then
		PlaceFilePath = Argument
	elseif (CustomOutputDirectory == nil) then
		CustomOutputDirectory = Argument
	else
		Stdio.ewrite(`Unexpected argument: {Argument}\n`)
		PrintHelp()
		Process.exit(1)
	end
	ArgumentIndex += 1
end

-- If no rbxl file provided, auto-detect in current directory
if (PlaceFilePath == nil) then
	local Candidates: {string} = {}
	for _, File in pairs(FileSystem.readDir(".")) do
		if (string.sub(File, -5) == ".rbxl" or string.sub(File, -6) == ".rbxlx") then
			table.insert(Candidates, File)
		end
	end
	if (#Candidates == 1) then
		PlaceFilePath = Candidates[1]
		print(`[INFO] Auto-detected place file: {PlaceFilePath}`)
	elseif (#Candidates > 1) then
		Stdio.ewrite("Multiple .rbxl files found in current directory. Please specify one:\n")
		for _, Candidate in ipairs(Candidates) do Stdio.ewrite("  - " .. Candidate .. "\n") end
		Process.exit(1)
	else
		Stdio.ewrite("Error: No .rbxl place file specified and none found in current directory.\n")
		PrintHelp()
		Process.exit(1)
	end
end

-- Validate rbxl file existence
if (not FileSystem.isFile(PlaceFilePath)) then
	Stdio.ewrite(`Error: File '{PlaceFilePath}' does not exist.\n`)
	Process.exit(1)
end

local PlaceStem = GetFileStem(PlaceFilePath)

-- Determine target output directory
local TargetDirectory = if (CustomOutputDirectory ~= nil) then CustomOutputDirectory
	elseif (UseDirectOutput) then "output"
	else "output/" .. PlaceStem
TargetDirectory = string.gsub(TargetDirectory, "\\", "/")
TargetDirectory = string.gsub(TargetDirectory, "/+$", "")

print(`Opening '{PlaceFilePath}'...`)
local StartTime = os.clock()

local FileContent: string
local ReadSuccess, ReadMessage = pcall(function()
	FileContent = FileSystem.readFile(PlaceFilePath)
end)
if (not ReadSuccess or FileContent == nil) then
	Stdio.ewrite(`Error reading file '{PlaceFilePath}': {tostring(ReadMessage)}\n`)
	Process.exit(1)
end

print(`Deserializing place data ({string.format("%.2f", #FileContent / (1024 * 1024))} MB)...`)
local Game: Roblox.Instance
local DeserializeSuccess, DeserializeMessage = pcall(function()
	Game = Roblox.deserializePlace(FileContent)
end)
if (not DeserializeSuccess or Game == nil) then
	Stdio.ewrite(`Error deserializing place: {tostring(DeserializeMessage)}\n`)
	Process.exit(1)
end

-- Locate and load .robignore
local RobIgnorePath: string? = nil
if (CustomIgnoreFile ~= nil) then
	if (FileSystem.isFile(CustomIgnoreFile)) then
		RobIgnorePath = CustomIgnoreFile
	else
		Stdio.ewrite(`Warning: Specified ignore file '{CustomIgnoreFile}' does not exist.\n`)
	end
elseif (FileSystem.isFile(".robignore")) then
	RobIgnorePath = ".robignore"
else
	local PlaceDirectory = string.match(PlaceFilePath, "^(.*)[/\\][^/\\]+$")
	if (PlaceDirectory and FileSystem.isFile(PlaceDirectory .. "/.robignore")) then
		RobIgnorePath = PlaceDirectory .. "/.robignore"
	end
end

local RobIgnoreRules: {IgnoreRule} = {}
if (RobIgnorePath ~= nil) then
	RobIgnoreRules = LoadRobIgnore(RobIgnorePath)
	print(
		`[INFO] Loaded ignore file '{RobIgnorePath}' ({#RobIgnoreRules} rule{if (#RobIgnoreRules == 1) then "" else "s"})`
	)
end

-- Ensure target directory exists
if (not FileSystem.isDir(TargetDirectory)) then FileSystem.writeDir(TargetDirectory) end

-- Find all scripts
local ScriptCounts: {[string]: number} = {
	ModuleScript = 0,
	Script = 0,
	LocalScript = 0,
	Total = 0
}

local WrittenPaths: {[string]: boolean} = {}
local DuplicateCount = 0
local IgnoredCount = 0

print("Traversing place hierarchy and extracting scripts...")

for _, Descendant in ipairs(Game:GetDescendants()) do
	local ClassName = Descendant.ClassName
	if (ClassName ~= "ModuleScript" and ClassName ~= "Script" and ClassName ~= "LocalScript") then continue end

	local RawAncestors: {string} = {}
	local PathSegments: {string} = {}
	local CurrentAncestor = Descendant.Parent
	while (CurrentAncestor and CurrentAncestor ~= Game) do
		table.insert(RawAncestors, 1, CurrentAncestor.Name)
		table.insert(PathSegments, 1, SanitizeName(CurrentAncestor.Name))
		CurrentAncestor = CurrentAncestor.Parent
	end

	local Ignored, _ = ShouldIgnore(RawAncestors, Descendant.Name, RobIgnoreRules)
	if (Ignored) then
		IgnoredCount += 1
		continue
	end

	ScriptCounts.Total += 1
	if (ScriptCounts[ClassName] ~= nil) then ScriptCounts[ClassName] += 1 end

	local ScriptName = SanitizeName(Descendant.Name)
	local RelativeDirectoryPath = table.concat(PathSegments, "/")
	local FullDirectoryPath = if (#RelativeDirectoryPath > 0) then TargetDirectory .. "/" .. RelativeDirectoryPath
		else TargetDirectory

	if (not FileSystem.isDir(FullDirectoryPath)) then FileSystem.writeDir(FullDirectoryPath) end

	local FileExtension = ".luau"
	if (UseRojoExtensions) then
		if (ClassName == "Script") then
			FileExtension = ".server.luau"
		elseif (ClassName == "LocalScript") then
			FileExtension = ".client.luau"
		else
			FileExtension = ".luau"
		end
	end

	local BaseFileName = ScriptName .. FileExtension
	local TargetFilePath = FullDirectoryPath .. "/" .. BaseFileName

	if (WrittenPaths[TargetFilePath]) then
		DuplicateCount += 1
		local Counter = 1
		repeat
			local AlternateFileName = `{ScriptName} ({Counter}){FileExtension}`
			TargetFilePath = FullDirectoryPath .. "/" .. AlternateFileName
			Counter += 1
		until not WrittenPaths[TargetFilePath]
		print(`  [!] Resolved collision for {BaseFileName} -> {TargetFilePath}`)
	end

	WrittenPaths[TargetFilePath] = true

	local Source = Descendant.Source or ""
	FileSystem.writeFile(TargetFilePath, Source)
end

local Elapsed = os.clock() - StartTime

print("--------------------------------------------------")
print(`Extraction completed in {string.format("%.2f", Elapsed)} seconds!`)
print(`Output directory: {TargetDirectory}`)
print(`Total scripts extracted: {ScriptCounts.Total}`)
print(`  - ModuleScripts: {ScriptCounts.ModuleScript}`)
print(`  - Server Scripts: {ScriptCounts.Script}`)
print(`  - LocalScripts:  {ScriptCounts.LocalScript}`)
if (IgnoredCount > 0) then print(`  - Ignored (.robignore): {IgnoredCount}`) end
if (DuplicateCount > 0) then print(`  - Name collisions resolved: {DuplicateCount}`) end
print("--------------------------------------------------")
