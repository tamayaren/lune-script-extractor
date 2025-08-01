--!strict
local fs = require("@lune/fs")
local Roblox = require("@lune/roblox")
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")

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

-- Parse CLI arguments
local RbxlPath: string? = nil
local CustomOutputDir: string? = nil
local CustomIgnoreFile: string? = nil
local OptDirect: boolean = false
local OptRojoExt: boolean = false

local RawArgs = {}
for _, arg in Process.args do
    if (arg ~= "--") then table.insert(RawArgs, arg) end
end

local ArgIdx = 1
while (ArgIdx <= #RawArgs) do
    local arg = RawArgs[ArgIdx]
    if (arg == "-h" or arg == "--help") then
        PrintHelp()
        Process.exit(0)
    elseif (arg == "--direct") then
        OptDirect = true
    elseif (arg == "--rojo-ext") then
        OptRojoExt = true
    elseif (arg == "--ignore-file") then
        ArgIdx += 1
        CustomIgnoreFile = RawArgs[ArgIdx]
        if (not CustomIgnoreFile) then
            Stdio.ewrite("Error: --ignore-file requires a file path argument.\n")
            Process.exit(1)
        end
    elseif (string.sub(arg, 1, 1) == "-") then
        Stdio.ewrite(string.format("Unknown option: %s\n", arg))
        PrintHelp()
        Process.exit(1)
    elseif (RbxlPath == nil) then
        RbxlPath = arg
    elseif (CustomOutputDir == nil) then
        CustomOutputDir = arg
    else
        Stdio.ewrite(string.format("Unexpected argument: %s\n", arg))
        PrintHelp()
        Process.exit(1)
    end
    ArgIdx += 1
end

-- If no rbxl file provided, auto-detect in current directory
if (RbxlPath == nil) then
    local Candidates = {}
    for _, File in fs.readDir(".") do
        if (string.sub(File, -5) == ".rbxl" or string.sub(File, -6) == ".rbxlx") then
            table.insert(Candidates, File)
        end
    end
    if (#Candidates == 1) then
        RbxlPath = Candidates[1]
        print(string.format("[INFO] Auto-detected place file: %s", RbxlPath))
    elseif (#Candidates > 1) then
        Stdio.ewrite("Multiple .rbxl files found in current directory. Please specify one:\n")
        for _, Candidate in Candidates do Stdio.ewrite("  - " .. Candidate .. "\n") end
        Process.exit(1)
    else
        Stdio.ewrite("Error: No .rbxl place file specified and none found in current directory.\n")
        PrintHelp()
        Process.exit(1)
    end
end

-- Validate rbxl file existence
if (not fs.isFile(RbxlPath)) then
    Stdio.ewrite(string.format("Error: File '%s' does not exist.\n", RbxlPath))
    Process.exit(1)
end

-- Extract base place name from file path
local function GetFileStem(FilePath: string): string
    local Normalized = string.gsub(FilePath, "\\", "/")
    local FileName = string.match(Normalized, "[^/]+$") or Normalized
    local Stem = string.gsub(FileName, "%.rbxlx?$", "")
    return Stem
end

local PlaceStem = GetFileStem(RbxlPath)

-- Determine target output directory
local TargetDir: string
if (CustomOutputDir ~= nil) then
    TargetDir = CustomOutputDir
elseif (OptDirect) then
    TargetDir = "output"
else
    TargetDir = "output/" .. PlaceStem
end
TargetDir = string.gsub(TargetDir, "\\", "/")
TargetDir = string.gsub(TargetDir, "/+$", "")

print(string.format("Opening '%s'...", RbxlPath))
local StartTime = os.clock()

local FileContent: string
local ReadSuccess, ReadErr = pcall(function()
    FileContent = fs.readFile(RbxlPath)
end)
if (not ReadSuccess or FileContent == nil) then
    Stdio.ewrite(string.format("Error reading file '%s': %s\n", RbxlPath, tostring(ReadErr)))
    Process.exit(1)
end

print(string.format("Deserializing place data (%.2f MB)...", #FileContent / (1024 * 1024)))
local Game: any
local DesSuccess, DesErr = pcall(function()
    Game = Roblox.deserializePlace(FileContent)
end)
if (not DesSuccess or Game == nil) then
    Stdio.ewrite(string.format("Error deserializing place: %s\n", tostring(DesErr)))
    Process.exit(1)
end

-- Helper to sanitize directory/file names for Windows and Unix filesystems
local function SanitizeName(Name: string): string
    local Sanitized = string.gsub(Name, '[<>:"/\\|?*\x00-\x1f]', "_")
    Sanitized = string.gsub(Sanitized, "[%.%s]+$", "")
    if (#Sanitized == 0) then Sanitized = "_unnamed" end
    
    local Upper = string.upper(Sanitized)
    local Reserved = {
        CON = true, PRN = true, AUX = true, NUL = true,
        COM1 = true, COM2 = true, COM3 = true, COM4 = true,
        COM5 = true, COM6 = true, COM7 = true, COM8 = true, COM9 = true,
        LPT1 = true, LPT2 = true, LPT3 = true, LPT4 = true,
        LPT5 = true, LPT6 = true, LPT7 = true, LPT8 = true, LPT9 = true,
    }
    if (Reserved[Upper]) then Sanitized ..= "_" end
    return Sanitized
end

-- .robignore support
type IgnoreRule = {
    Raw: string,
    IsNegated: boolean,
    IsDirOnly: boolean,
    HasSlash: boolean,
    Pattern: string,
}

local function GlobToPattern(Glob: string): string
    local Pattern = string.gsub(Glob, "([%%%^%$%(%)%%.%[%]%+%-])", "%%%1")
    Pattern = string.gsub(Pattern, "%*", ".*")
    Pattern = string.gsub(Pattern, "%?", ".")
    return "^" .. Pattern .. "$"
end

local function LoadRobIgnore(FilePath: string): {IgnoreRule}
    local Rules = {}
    if (not fs.isFile(FilePath)) then return Rules end

    local Content = fs.readFile(FilePath)
    for Line in string.gmatch(Content, "[^\r\n]+") do
        Line = string.gsub(Line, "^%s+", "")
        Line = string.gsub(Line, "%s+$", "")
        if (#Line > 0 and string.sub(Line, 1, 1) ~= "#") then
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
                Pattern = RegexPattern,
            })
        end
    end
    return Rules
end

local function ShouldIgnore(AncestorNames: {string}, ScriptName: string, Rules: {IgnoreRule}): (boolean, string?)
    if (#Rules == 0) then return false, nil end

    local FullDirPath = table.concat(AncestorNames, "/")
    local FullPath = if (#FullDirPath > 0) then FullDirPath .. "/" .. ScriptName else ScriptName
    local FullPathWithExt = FullPath .. ".luau"
    local ImmediateParent = AncestorNames[#AncestorNames] or ""

    local Ignored = false
    local MatchedRule: string? = nil

    for _, Rule in Rules do
        local Matched = false
        if (Rule.HasSlash) then
            if (string.match(FullPath, Rule.Pattern)
                or string.match(FullPathWithExt, Rule.Pattern)
                or string.match(FullDirPath, Rule.Pattern)
                or string.find(FullPath, Rule.Raw, 1, true)
                or string.find(FullDirPath, Rule.Raw, 1, true)) then
                Matched = true
            end
        else
            if (string.match(ImmediateParent, Rule.Pattern) or ImmediateParent == Rule.Raw) then
                Matched = true
            else
                for _, anc in AncestorNames do
                    if (string.match(anc, Rule.Pattern) or anc == Rule.Raw) then
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

-- Locate and load .robignore
local RobIgnorePath: string? = nil
if (CustomIgnoreFile ~= nil) then
    if (fs.isFile(CustomIgnoreFile)) then
        RobIgnorePath = CustomIgnoreFile
    else
        Stdio.ewrite(string.format("Warning: Specified ignore file '%s' does not exist.\n", CustomIgnoreFile))
    end
elseif (fs.isFile(".robignore")) then
    RobIgnorePath = ".robignore"
else
    local ParentOfRbxl = string.match(RbxlPath, "^(.*)[/\\][^/\\]+$")
    if (ParentOfRbxl and fs.isFile(ParentOfRbxl .. "/.robignore")) then
        RobIgnorePath = ParentOfRbxl .. "/.robignore"
    end
end

local RobIgnoreRules: {IgnoreRule} = {}
if (RobIgnorePath ~= nil) then
    RobIgnoreRules = LoadRobIgnore(RobIgnorePath)
    print(string.format("[INFO] Loaded ignore file '%s' (%d rule%s)", RobIgnorePath, #RobIgnoreRules, if (#RobIgnoreRules == 1) then "" else "s"))
end

-- Ensure target directory exists
if (not fs.isDir(TargetDir)) then fs.writeDir(TargetDir) end

-- Find all scripts
local ScriptCounts = {
    ModuleScript = 0,
    Script = 0,
    LocalScript = 0,
    Total = 0,
}

local WrittenPaths: { [string]: boolean } = {}
local DuplicateCount = 0
local IgnoredCount = 0

print("Traversing place hierarchy and extracting scripts...")

for _, Desc in Game:GetDescendants() do
    local ClassName = Desc.ClassName
    if (ClassName == "ModuleScript" or ClassName == "Script" or ClassName == "LocalScript") then
        local RawAncestors = {}
        local PathSegments = {}
        local Curr = Desc.Parent
        while (Curr and Curr ~= Game) do
            table.insert(RawAncestors, 1, Curr.Name)
            table.insert(PathSegments, 1, SanitizeName(Curr.Name))
            Curr = Curr.Parent
        end

        local Ignored, _ = ShouldIgnore(RawAncestors, Desc.Name, RobIgnoreRules)
        if (Ignored) then
            IgnoredCount += 1
            continue
        end

        ScriptCounts.Total += 1
        if (ScriptCounts[ClassName] ~= nil) then ScriptCounts[ClassName] += 1 end

        local ScriptName = SanitizeName(Desc.Name)
        local RelDirPath = table.concat(PathSegments, "/")
        local FullDirPath = if (#RelDirPath > 0) then TargetDir .. "/" .. RelDirPath else TargetDir

        if (not fs.isDir(FullDirPath)) then fs.writeDir(FullDirPath) end

        local FileExt = ".luau"
        if (OptRojoExt) then
            if (ClassName == "Script") then
                FileExt = ".server.luau"
            elseif (ClassName == "LocalScript") then
                FileExt = ".client.luau"
            else
                FileExt = ".luau"
            end
        end

        local BaseFileName = ScriptName .. FileExt
        local TargetFilePath = FullDirPath .. "/" .. BaseFileName

        if (WrittenPaths[TargetFilePath]) then
            DuplicateCount += 1
            local Counter = 1
            repeat
                local AltFileName = string.format("%s (%d)%s", ScriptName, Counter, FileExt)
                TargetFilePath = FullDirPath .. "/" .. AltFileName
                Counter += 1
            until not WrittenPaths[TargetFilePath]
            print(string.format("  [!] Resolved collision for %s -> %s", BaseFileName, TargetFilePath))
        end

        WrittenPaths[TargetFilePath] = true

        local Source = Desc.Source or ""
        fs.writeFile(TargetFilePath, Source)
    end
end

local Elapsed = os.clock() - StartTime

print("--------------------------------------------------")
print(string.format("Extraction completed in %.2f seconds!", Elapsed))
print(string.format("Output directory: %s", TargetDir))
print(string.format("Total scripts extracted: %d", ScriptCounts.Total))
print(string.format("  - ModuleScripts: %d", ScriptCounts.ModuleScript))
print(string.format("  - Server Scripts: %d", ScriptCounts.Script))
print(string.format("  - LocalScripts:  %d", ScriptCounts.LocalScript))
if (IgnoredCount > 0) then print(string.format("  - Ignored (.robignore): %d", IgnoredCount)) end
if (DuplicateCount > 0) then print(string.format("  - Name collisions resolved: %d", DuplicateCount)) end
print("--------------------------------------------------")
