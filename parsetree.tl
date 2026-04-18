local common = require("common")

local record parsetree
    interface Node
        where self.kind

        kind: string
        position: common.Position
    end

    record MinecraftTextNode
        is Node
        where self.kind == "MinecraftTextNode"

        components: {TextComponent}
    end

    type TextComponent = VoidTagNode | NormalTagNode | PlainTextNode

    type VoidTagNode = NewlineNode | NewlineNode

    record NewlineNode
        is Node
        where self.kind == "NewlineNode"
    end

    interface NormalTagNode
        is Node
        where self.kind

        components: {TextComponent}
    end

    record NamedColorNode
        is NormalTagNode
        where self.kind == "NamedColorNode"

        color: NamedColor
    end

    type NamedColor = enum "black" "dark_blue" "dark_green" "dark_aqua" "dark_red" "dark_purple" "gold" "gray" "dark_gray" "blue" "green" "aqua" "red" "light_purple" "yellow" "white" end

    record HexColorNode
        is NormalTagNode
        where self.kind == "HexColorNode"

        color: string  -- 6 digit hex code without the `#` symbol
    end

    record DecorationNode
        is NormalTagNode
        where self.kind == "DecorationNode"

        decoration: Decoration
    end

    type Decoration = enum "bold" "italic" "underlined" "strikethrough" "obfuscated" end

    type HoverNode = ShowTextNode | ShowTextNode

    record ShowTextNode
        is NormalTagNode
        where self.kind == "ShowTextNode"

        tooltip: MinecraftTextNode
    end

    record PlainTextNode
        is NormalTagNode
        where self.kind == "PlainTextNode"

        content: string
    end

end

function parsetree.MinecraftTextNode.new(position: common.Position, components: {parsetree.TextComponent}): parsetree.MinecraftTextNode
    local self: parsetree.MinecraftTextNode = setmetatable({}, { __index = parsetree.MinecraftTextNode })
    self.kind = "MinecraftTextNode"
    self.position = position
    self.components = components
    return self
end

function parsetree.NewlineNode.new(position: common.Position): parsetree.NewlineNode
    local self: parsetree.NewlineNode = setmetatable({}, { __index = parsetree.NewlineNode })
    self.kind = "NewlineNode"
    self.position = position
    return self
end

function parsetree.NamedColorNode.new(position: common.Position, color: parsetree.NamedColor, components: {parsetree.TextComponent}): parsetree.NamedColorNode
    local self: parsetree.NamedColorNode = setmetatable({}, { __index = parsetree.NamedColorNode })
    self.kind = "NamedColorNode"
    self.position = position
    self.color = color
    self.components = components
    return self
end

function parsetree.HexColorNode.new(position: common.Position, color: string, components: {parsetree.TextComponent}): parsetree.HexColorNode
    assert(#color == 6)
    local self: parsetree.HexColorNode = setmetatable({}, { __index = parsetree.HexColorNode })
    self.kind = "HexColorNode"
    self.position = position
    self.color = color
    self.components = components
    return self
end

function parsetree.DecorationNode.new(position: common.Position, decoration: parsetree.Decoration, components: {parsetree.TextComponent}): parsetree.DecorationNode
    local self: parsetree.DecorationNode = setmetatable({}, { __index = parsetree.DecorationNode })
    self.kind = "DecorationNode"
    self.position = position
    self.decoration = decoration
    self.components = components
    return self
end

function parsetree.ShowTextNode.new(position: common.Position, tooltip: parsetree.MinecraftTextNode, components: {parsetree.TextComponent}): parsetree.ShowTextNode
    local self: parsetree.ShowTextNode = setmetatable({}, { __index = parsetree.ShowTextNode })
    self.kind = "ShowTextNode"
    self.position = position
    self.tooltip = tooltip
    self.components = components
    return self
end

function parsetree.PlainTextNode.new(position: common.Position, content: string): parsetree.PlainTextNode
    local self: parsetree.PlainTextNode = setmetatable({}, { __index = parsetree.PlainTextNode })
    self.kind = "PlainTextNode"
    self.position = position
    self.content = content
    return self
end

return parsetree

