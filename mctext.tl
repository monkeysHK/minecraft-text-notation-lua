local common = require("common")
local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local record mctext

    type CompileResult = CompileAccept | CompileFail

    record CompileAccept
        where self.kind == "CompileAccept"

        kind: string
        result: string
        warnings: {common.Problem}
    end

    record CompileFail
        where self.kind == "CompileFail"

        kind: string
        errors: {common.Problem}
    end

    record CompileOptions
        useStrictMode: boolean | nil  -- default false
    end

end

function mctext.CompileAccept.new(result: string, warnings: {common.Problem}): mctext.CompileAccept
    local self: mctext.CompileAccept = setmetatable({}, { __index = mctext.CompileAccept })
    self.kind = "CompileAccept"
    self.result = result
    self.warnings = warnings
    return self
end

function mctext.CompileFail.new(errors: {common.Problem}): mctext.CompileFail
    local self: mctext.CompileFail = setmetatable({}, { __index = mctext.CompileFail })
    self.kind = "CompileFail"
    self.errors = errors
    return self
end

function mctext.CompileOptions.new(useStrictMode: boolean | nil): mctext.CompileOptions
    local self: mctext.CompileOptions = setmetatable({}, { __index = mctext.CompileOptions })
    self.useStrictMode = useStrictMode
    return self
end

function mctext.compile(text: string, options: mctext.CompileOptions): mctext.CompileResult
    local warnings: {common.Problem} = {}

    local function addWarnings(newWarnings: {common.Problem})
        for _, warning in ipairs(newWarnings) do
            warnings[#warnings + 1] = warning
        end
    end

    local tokens = lexer.tokenize(text)

    addWarnings(tokens.warnings)

    local ast = parser.parse(tokens.result)

    if options.useStrictMode then
        addWarnings(ast.strictProblems)
    end

    addWarnings(ast.warnings)

    if options.useStrictMode then
        if #warnings > 0 then
            return mctext.CompileFail.new(warnings)
        end
    end

    local result = codegen.generate(ast.result)

    return mctext.CompileAccept.new(result, warnings)
end

return mctext

