local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local function extractResult(parseResult)
    assert.equal("CompileAccept", parseResult.kind)
    assert.equal("string", type(parseResult.result))
    assert.equal("table", type(parseResult.warnings))
    return parseResult.result, parseResult.warnings
end

local function extractResultNoWarn(parseResult)
    local result, warnings = extractResult(parseResult)
    assert.are.same({}, warnings, "expect result has no warning")
    return result
end

local function extractErrors(parseResult)
    assert.equal("CompileFail", parseResult.kind)
    assert.equal("table", type(parseResult.errors))
    return parseResult.errors
end

local function position(index, row, col)
    return lexer.makePosition(index, row, col)
end

local function lineonepos(index)
    return lexer.makePosition(index, 1, index)
end

local function problem(message, position)
    return lexer.makeProblem(message, position)
end

local function minecraftText(position, components)
    return parser.makeMinecraftText(position, components)
end

local function namedColor(position, color, components)
    return parser.makeNamedColor(position, color, components)
end

local function hexColor(position, color, components)
    return parser.makeHexColor(position, color, components)
end

local function decoration(position, decorationName, components)
    return parser.makeDecoration(position, decorationName, components)
end

local function showText(position, text, textPosition, originalString, components)
    return parser.makeShowText(position, text, textPosition, originalString, components)
end

local function newline(position)
    return parser.makeNewline(position)
end

local function plainText(position, content)
    return parser.makePlainText(position, content)
end

describe("node generation", function()

    it("expect plain text is generated", function()
        local output = codegen.generate(minecraftText(lineonepos(1), {plainText(lineonepos(1), "some text")}), {})
        local result = extractResultNoWarn(output)

        assert.are.same("some text", result)
    end)

    it("expect newline node is generated", function()
        local output = codegen.generate(minecraftText(lineonepos(1), {newline(lineonepos(1))}), {})
        local result = extractResultNoWarn(output)

        assert.are.same("<br>", result)
    end)

    it("expect named color node is generated", function()
        local namedColors = { "black", "dark_blue", "dark_green", "dark_aqua", "dark_red", "dark_purple", "gold", "gray", "dark_gray", "blue", "green", "aqua", "red", "light_purple", "yellow", "white" }
        for _, color in ipairs(namedColors) do
            local output = codegen.generate(minecraftText(lineonepos(1),{namedColor(lineonepos(1), color, {})}), {})
            local result = extractResultNoWarn(output)

            assert.are.same('<span class="mcformat-' .. color .. '"></span>', result)
        end
    end)

    it("expect hex color node is generated", function()
        local output = codegen.generate(minecraftText(lineonepos(1), {hexColor(lineonepos(1), "abcdef", {})}), {})
        local result = extractResultNoWarn(output)

        assert.are.same('<span style="color: #abcdef;"></span>', result)
    end)

    it("expect decoration node is generated", function()
        local decorations = { "bold", "italic", "underlined", "strikethrough", "obfuscated" }

        for _, decorationName in ipairs(decorations) do
            local output = codegen.generate(minecraftText(lineonepos(1), {decoration(lineonepos(1), decorationName, {})}), {})
            local result = extractResultNoWarn(output)

            assert.are.same('<span class="mcformat-' .. decorationName .. '"></span>', result)
        end
    end)

    it("expect show text node is generated with secondary parsing on text", function()
        local output = codegen.generate(minecraftText(lineonepos(1), {showText(lineonepos(1), "<yellow>hovered text", lineonepos(18), "'<yellow>hovered text'", {})}), {})
        local result = extractResultNoWarn(output)

        assert.are.same('<span><span class="mctooltip"><span class="mcformat-yellow">hovered text</span></span></span>', result)
    end)

end)

describe("warning and error generation", function()

    it("expect lexer and parser warnings are generated", function()
        local output = codegen.compile("<unknown>some text\\", {})
        local result, warnings = extractResult(output)

        assert.are.same('<unknown>some text\\', result)
        assert.are.same({
            problem("invalid escape \\", lineonepos(19)),  -- warning from lexer
            problem("unknown tag unknown", lineonepos(1)),  -- warning from parser
        }, warnings)
    end)

    it("expect lexer warnings cause failure on strict mode", function()
        local output = codegen.compile("<unknown>some text\\", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("invalid escape \\", lineonepos(19)) }, errors)
    end)

    it("expect parser warnings cause failure on strict mode", function()
        local output = codegen.compile("<unknown>some text", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("unknown tag unknown", lineonepos(1)) }, errors)
    end)

    it("expect parser strict problems cause failure on strict mode", function()
        local output = codegen.compile("<yellow>some text", { useStrictMode = true })
        local errors = extractErrors(output)

        assert.are.same({ problem("tag yellow does not have an end tag", lineonepos(1)) }, errors)
    end)

    describe("secondary parsing warnings and strict problems", function()

        it("expect single line warning position to be correct", function()
            local output = codegen.compile("some text<hover:show_text:'before<unknown>after'>", {})
            local _, warnings = extractResult(output)

            assert.are.same({ problem("unknown tag unknown", lineonepos(34)) }, warnings)
        end)

        it("expect multi line warning position to be correct", function()
            local output = codegen.compile("some text\n<hover:show_text:'<unknown>\n</unknown>after'>", {})
            local _, warnings = extractResult(output)

            assert.are.same({
                problem("unknown tag unknown", position(29, 2, 19)),
                problem("invalid end tag unknown", position(39, 3, 1)),
            }, warnings)
        end)

        it("expect errors on strict mode are propagated", function()
            local output = codegen.compile("some text<hover:show_text:'<yellow>some text'></hover>", { useStrictMode = true })
            local errors = extractErrors(output)

            assert.are.same({ problem("tag yellow does not have an end tag", lineonepos(28)) }, errors)
        end)

    end)

end)

it("expect consecutive nodes are generated", function()
    local output = codegen.generate(minecraftText(lineonepos(1), {
        plainText(lineonepos(1), "Line 1"),
        newline(lineonepos(7)),
        plainText(position(8, 2, 1), "\\"),
    }), {})
    local result = extractResultNoWarn(output)

    assert.are.same('Line 1<br>\\', result)
end)

it("expect nested nodes are generated", function()
    local output = codegen.generate(minecraftText(lineonepos(1), {
        decoration(lineonepos(1), "bold", {
            decoration(lineonepos(4), "italic", {
                plainText(lineonepos(7), "some text")
            })
        }),
        decoration(lineonepos(23), "underlined", {
            plainText(lineonepos(26), "some text")
        })
    }), {})
    local result = extractResultNoWarn(output)

    assert.are.same('<span class="mcformat-bold"><span class="mcformat-italic">some text</span></span><span class="mcformat-underlined">some text</span>', result)
end)


