local common = require("common")
local mctext = require("mctext")

local function extractResult(compileResult)
    assert.equal("CompileAccept", compileResult.kind)
    assert.equal("string", type(compileResult.result))
    assert.equal("table", type(compileResult.warnings))
    return compileResult.result, compileResult.warnings
end

local function extractResultNoWarn(compileResult)
    local result, warnings = extractResult(compileResult)
    assert.are.same({}, warnings, "expect result has no warning")
    return result
end

local function extractErrors(compileResult)
    assert.equal("CompileFail", compileResult.kind)
    assert.equal("table", type(compileResult.errors))
    return compileResult.errors
end

local function position(index, row, col)
    return common.Position.new(index, row, col)
end

local function lineonepos(index)
    return common.Position.new(index, 1, index)
end

local function problem(message, position)
    return common.Problem.new(message, position)
end

it("expect compiler can generate correct cases (non-strict mode)", function()
    local tests = {
        { input = "some text", result = "some text" },
        { input = "<br>", result = "<br>" },
        { input = "<color:'#abcdef'>", result = '<span style="color: #abcdef;"></span>' },
        { input = "<hover:show_text:'<yellow>hovered text'>", result = '<span><span class="mctooltip"><span class="mcformat-yellow">hovered text</span></span></span>' },
        { input = "line 1\n\\\\", result = "line 1<br>\\" },
        { input = "<b><i>some text<reset><u>some text", result = '<span class="mcformat-bold"><span class="mcformat-italic">some text</span></span><span class="mcformat-underlined">some text</span>' }
    }

    for _, test in ipairs(tests) do
        local output = mctext.compile(test.input, {})
        local result = extractResultNoWarn(output)

        assert.are.same(test.result, result)
    end
end)

it("expect compiler can generate correct cases (strict mode)", function()
    local tests = {
        { input = "some text", result = "some text" },
        { input = "<br>", result = "<br>" },
        { input = "<color:'#abcdef'></color>", result = '<span style="color: #abcdef;"></span>' },
        { input = "<hover:show_text:'<yellow>hovered text</yellow>'></hover>", result = '<span><span class="mctooltip"><span class="mcformat-yellow">hovered text</span></span></span>' },
        { input = "line 1\n\\\\", result = "line 1<br>\\" },
        { input = "<b><i>some text</i></b><u>some text</u>", result = '<span class="mcformat-bold"><span class="mcformat-italic">some text</span></span><span class="mcformat-underlined">some text</span>' }
    }

    for _, test in ipairs(tests) do
        local output = mctext.compile(test.input, { useStrictMode = true })
        local result = extractResultNoWarn(output)

        assert.are.same(test.result, result)
    end
end)

describe("warning and error generation", function()

    it("expect lexer and parser warnings are generated", function()
        local output = mctext.compile("<unknown>some text\\", {})
        local result, warnings = extractResult(output)

        assert.are.same('<unknown>some text\\', result)
        assert.are.same({
            problem("invalid escape \\", lineonepos(19)),  -- warning from lexer
            problem("unknown tag unknown", lineonepos(1)),  -- warning from parser
        }, warnings)
    end)

    it("expect lexer warnings cause failure on strict mode", function()
        local output = mctext.compile("some text\\", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("invalid escape \\", lineonepos(10)) }, errors)
    end)

    it("expect parser warnings cause failure on strict mode", function()
        local output = mctext.compile("<unknown>some text", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("unknown tag unknown", lineonepos(1)) }, errors)
    end)

    it("expect parser strict problems cause failure on strict mode", function()
        local output = mctext.compile("<yellow>some text", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("tag yellow does not have an end tag", lineonepos(1)) }, errors)
    end)

    describe("secondary parsing warnings and strict problems", function()

        it("expect single line warning position to be correct", function()
            local output = mctext.compile("some text<hover:show_text:'before<unknown>after'>", {})
            local _, warnings = extractResult(output)

            assert.are.same({ problem("unknown tag unknown", lineonepos(34)) }, warnings)
        end)

        it("expect multi line warning position to be correct", function()
            local output = mctext.compile("some text\n<hover:show_text:'<unknown>\n</unknown>after'>", {})
            local _, warnings = extractResult(output)

            assert.are.same({
                problem("unknown tag unknown", position(29, 2, 19)),
                problem("invalid end tag unknown", position(39, 3, 1)),
            }, warnings)
        end)

    end)

end)

