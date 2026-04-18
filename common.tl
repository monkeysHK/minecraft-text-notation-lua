local record common
    record Position
        index: integer
        line: integer
        col: integer
    end

    record Problem
        position: Position
        message: string
    end

    type ParseResult<T> = ParseAccept<T> | ParseReject | ParseFail

    -- Used when lexer/parser successfully parses a token/node
    record ParseAccept<T>
        where self.kind == "ParseAccept"

        kind: string
        result: T
        nextIndex: integer
        warnings: {Problem}  -- problems that are errors in strict mode, and should be corrected in non-strict mode
        strictProblems: {Problem}  -- problems that are errors in strict mode and are valid in non-strict mode
    end

    -- Used when lexer/parser determines that this is not the required token/node
    record ParseReject
        where self.kind == "ParseReject"

        kind: string
    end

    -- Used when lexer/parser determines that this is the required token/node
    -- but something was wrong
    record ParseFail
        where self.kind == "ParseFail"

        kind: string
        failure: Problem
    end

end

function common.Position.new(index: integer, line: integer, col: integer): common.Position
    local self: common.Position = setmetatable({}, { __index = common.Position })
    self.index = index
    self.line = line
    self.col = col
    return self
end

function common.Position:advance(offset: integer): common.Position
    return common.Position.new(self.index + offset, self.line, self.col + offset)
end

function common.Position:toGlobalPosition(parentPosition: common.Position): common.Position
    local index = parentPosition.index + self.index - 1
    local line = parentPosition.line + self.line - 1
    local onSameLine = self.line == 1
    local col = onSameLine and (parentPosition.col + self.col - 1) or self.col
    return common.Position.new(index, line, col)
end

function common.Problem.new(message: string, position: common.Position): common.Problem
    local self: common.Problem = setmetatable({}, { __index = common.Problem })
    self.message = message
    self.position = position
    return self
end

function common.ParseAccept.new<T>(result: T, nextIndex: integer, warnings: {common.Problem}, strictProblems: {common.Problem}): common.ParseAccept<T>
    local self: common.ParseAccept<T> = setmetatable({}, { __index = common.ParseAccept })
    self.kind = "ParseAccept"
    self.result = result
    self.nextIndex = nextIndex
    self.warnings = warnings
    self.strictProblems = strictProblems
    return self
end

function common.ParseReject.new(): common.ParseReject
    local self: common.ParseReject = setmetatable({}, { __index = common.ParseReject })
    self.kind = "ParseReject"
    return self
end

function common.ParseFail.new(failure: common.Problem): common.ParseFail
    local self: common.ParseFail = setmetatable({}, { __index = common.ParseFail })
    self.kind = "ParseFail"
    self.failure = failure
    return self
end

return common

