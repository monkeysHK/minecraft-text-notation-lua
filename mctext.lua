local common = require("common")
local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local mctext = { CompileAccept = {}, CompileFail = {}, CompileOptions = {} }
























function mctext.CompileAccept.new(result, warnings)
   local self = setmetatable({}, { __index = mctext.CompileAccept })
   self.kind = "CompileAccept"
   self.result = result
   self.warnings = warnings
   return self
end

function mctext.CompileFail.new(errors)
   local self = setmetatable({}, { __index = mctext.CompileFail })
   self.kind = "CompileFail"
   self.errors = errors
   return self
end

function mctext.CompileOptions.new(useStrictMode)
   local self = setmetatable({}, { __index = mctext.CompileOptions })
   self.useStrictMode = useStrictMode
   return self
end

function mctext.compile(text, options)
   local warnings = {}

   local function addWarnings(newWarnings)
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
