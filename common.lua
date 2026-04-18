local common = { Position = {}, Problem = {}, ParseAccept = {}, ParseReject = {}, ParseFail = {} }










































function common.Position.new(index, line, col)
   local self = setmetatable({}, { __index = common.Position })
   self.index = index
   self.line = line
   self.col = col
   return self
end

function common.Position:advance(offset)
   return common.Position.new(self.index + offset, self.line, self.col + offset)
end

function common.Position:toGlobalPosition(parentPosition)
   local index = parentPosition.index + self.index - 1
   local line = parentPosition.line + self.line - 1
   local onSameLine = self.line == 1
   local col = onSameLine and (parentPosition.col + self.col - 1) or self.col
   return common.Position.new(index, line, col)
end

function common.Problem.new(message, position)
   local self = setmetatable({}, { __index = common.Problem })
   self.message = message
   self.position = position
   return self
end

function common.ParseAccept.new(result, nextIndex, warnings, strictProblems)
   local self = setmetatable({}, { __index = common.ParseAccept })
   self.kind = "ParseAccept"
   self.result = result
   self.nextIndex = nextIndex
   self.warnings = warnings
   self.strictProblems = strictProblems
   return self
end

function common.ParseReject.new()
   local self = setmetatable({}, { __index = common.ParseReject })
   self.kind = "ParseReject"
   return self
end

function common.ParseFail.new(failure)
   local self = setmetatable({}, { __index = common.ParseFail })
   self.kind = "ParseFail"
   self.failure = failure
   return self
end

return common
