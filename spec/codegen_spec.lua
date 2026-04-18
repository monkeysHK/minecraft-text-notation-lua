local common = require("common")
local parsetree = require("parsetree")
local codegen = require("codegen")

local function position(index, row, col)
    return common.Position.new(index, row, col)
end

local function lineonepos(index)
    return common.Position.new(index, 1, index)
end

local function minecraftText(position, components)
    return parsetree.MinecraftTextNode.new(position, components)
end

local function namedColor(position, color, components)
    return parsetree.NamedColorNode.new(position, color, components)
end

local function hexColor(position, color, components)
    return parsetree.HexColorNode.new(position, color, components)
end

local function decoration(position, decorationName, components)
    return parsetree.DecorationNode.new(position, decorationName, components)
end

local function showText(position, tooltip, components)
    return parsetree.ShowTextNode.new(position, tooltip, components)
end

local function newline(position)
    return parsetree.NewlineNode.new(position)
end

local function plainText(position, content)
    return parsetree.PlainTextNode.new(position, content)
end

describe("node generation", function()

    it("expect plain text is generated", function()
        -- test case: some text
        local result = codegen.generate(minecraftText(lineonepos(1), {plainText(lineonepos(1), "some text")}))

        assert.are.same("some text", result)
    end)

    it("expect newline node is generated", function()
        -- test case: <br>
        local result = codegen.generate(minecraftText(lineonepos(1), {newline(lineonepos(1))}))

        assert.are.same("<br>", result)
    end)

    it("expect named color node is generated", function()
        local namedColors = { "black", "dark_blue", "dark_green", "dark_aqua", "dark_red", "dark_purple", "gold", "gray", "dark_gray", "blue", "green", "aqua", "red", "light_purple", "yellow", "white" }
        for _, color in ipairs(namedColors) do
            local result = codegen.generate(minecraftText(lineonepos(1),{namedColor(lineonepos(1), color, {})}))

            assert.are.same('<span class="mcformat-' .. color .. '"></span>', result)
        end
    end)

    it("expect hex color node is generated", function()
        -- test case: "<color:'#abcdef'>"
        local result = codegen.generate(minecraftText(lineonepos(1), {hexColor(lineonepos(1), "abcdef", {})}))

        assert.are.same('<span style="color: #abcdef;"></span>', result)
    end)

    it("expect decoration node is generated", function()
        local decorations = { "bold", "italic", "underlined", "strikethrough", "obfuscated" }

        for _, decorationname in ipairs(decorations) do
            local result = codegen.generate(minecraftText(lineonepos(1), {decoration(lineonepos(1), decorationname, {})}))

            assert.are.same('<span class="mcformat-' .. decorationname .. '"></span>', result)
        end
    end)

    it("expect show text node is generated", function()
        -- test case: <hover:show_text:'<yellow>hovered text'>
        local tooltip = minecraftText(lineonepos(19), {namedColor(lineonepos(19), "yellow", {plainText(lineonepos(27), "hovered text")})})
        local result = codegen.generate(minecraftText(lineonepos(1), {showText(lineonepos(1), tooltip, {})}))

        assert.are.same('<span><span class="mctooltip"><span class="mcformat-yellow">hovered text</span></span></span>', result)
    end)

end)

it("expect consecutive nodes are generated", function()
    -- test case: line 1
    -- \\
    local result = codegen.generate(minecraftText(lineonepos(1), {
        plainText(lineonepos(1), "line 1"),
        newline(lineonepos(7)),
        plainText(position(8, 2, 1), "\\"),
    }))

    assert.are.same('line 1<br>\\', result)
end)

it("expect nested nodes are generated", function()
    -- test case: <b><i>some text<reset><u>some text
    local result = codegen.generate(minecraftText(lineonepos(1), {
        decoration(lineonepos(1), "bold", {
            decoration(lineonepos(4), "italic", {
                plainText(lineonepos(7), "some text")
            })
        }),
        decoration(lineonepos(16), "underlined", {
            plainText(lineonepos(19), "some text")
        })
    }))

    assert.are.same('<span class="mcformat-bold"><span class="mcformat-italic">some text</span></span><span class="mcformat-underlined">some text</span>', result)
end)

